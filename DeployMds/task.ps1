[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation

try
{
    [string]$mdsServer = Get-VstsInput -Name mdsServer -Require
    [string]$mdsUsername = Get-VstsInput -Name mdsUsername -Require
    [string]$mdsPassword = Get-VstsInput -Name mdsPassword -Require    
    [string]$mdsService = Get-VstsInput -Name mdsService -Require
    [string]$sqlServerVersion = Get-VstsInput -Name ssVersion
    [string]$mdsDatabaseInstance = Get-VstsInput -Name mdsDatabaseInstance -Require
    [string]$mdsDatabase = Get-VstsInput -Name mdsDatabase -Require
    [string]$mdsPackages = Get-VstsInput -Name mdsPackages -Require
    [string]$mdsDeploymentType = Get-VstsInput -Name mdsDeploymentType -Require
    [string]$mdsVersion = Get-VstsInput -Name mdsVersion
    [string]$mdsModel = Get-VstsInput -Name mdsModel
    [bool]$validate = Get-VstsInput -Name validate -AsBool

    Import-Module -Name $PSScriptRoot\ps_modules\Mds.psm1 -Force

    $securePassword = ConvertTo-SecureString -String $mdsPassword -asPlainText -Force
    $mdsCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $mdsUsername, $securePassword

    $mdsServer = Resolve-HostNameOrAddress $mdsServer
    
    $session = New-PSSession -ComputerName $mdsServer -Credential $mdsCredential
    $sid = Get-UserSid($mdsUsername)

    $mdsExecutable = Get-MdsPath -Session $session -SqlServerVersion $sqlServerVersion
    $tempFolder = New-TemporaryFolder -Session $session

    if ($sqlServerVersion -eq "110" -or $sqlServerVersion -eq "120")
    {
        # Get the current MDS Administrator
        $oldAdmin = Get-Administrator -databaseInstance $mdsDatabaseInstance -databaseName $mdsDatabase
        Write-Verbose "Current MDS admin is '$($oldAdmin.UserName)'."

        Set-Administrator -databaseInstance $mdsDatabaseInstance -databaseName $mdsDatabase -sid $sid -username $mdsUsername
        Write-Output "MDS admin is set to '$mdsUsername'."
    }

    # Get all packages that should be deployed
    if ($mdsPackages.Contains("*") -or $mdsPackages.Contains("?"))
    {
        $packageFiles = Find-VstsFiles -LegacyPattern $mdsPackages
        if (!$packageFiles.Count)
        {
            throw "No packages to deploy were found."
        }
    }
    else
    {
        $packageFiles = ,$mdsPackages
    }

    $localPackages = @()

    foreach ($package in $packageFiles)
    {
        Write-Output "Found local package '$package'"

        $converted = [System.IO.FileInfo]$package

        if ($converted.Exists -and $converted.Extension -eq ".pkg")
        {
            $localPackages += $converted
        }
        else
        {
            throw "Package $package is not a valid MDS package."
        }
    }

    # Transfer all of the files in the temp folder on the host machine
    $localPackages | Copy-Item -Destination $tempFolder -Force -Recurse -Container -ToSession $session
    $remotePackages = $localPackages | ForEach-Object { Join-Path $tempFolder $_.Name }

    try 
    {
        Publish-MdsPackages $remotePackages $mdsExecutable $mdsService $mdsDeploymentType $mdsVersion $mdsModel $session
    }
    catch
    {
        $errorLines = $_.Exception.Message -split "`r`n"

        foreach ($errorLine in $errorLines)
        {
            Write-VstsTaskError -Message $errorLine
        }

        Write-VstsSetResult -Result 'Failed' -Message "Error detected" -DoNotThrow
    }
}
finally
{
    if ($sqlServerVersion -eq "110" -or $sqlServerVersion -eq "120")
    {
        # Set the MDS Adminstrator back to the initial user that was stored in $oldAdmin
        Set-Administrator -databaseInstance $mdsDatabaseInstance -databaseName $mdsDatabase -sid $oldAdmin.SID -username $oldAdmin.UserName -displayName $oldAdmin.DisplayName -description $oldAdmin.Description -emailAddress $oldAdmin.EmailAddress
        Write-Output "MDS admin is reset to '$($oldAdmin.UserName)'."
    }

    if ($session -ne $null)
    { 
        $deleteTempFolder = { param($folder) if (Test-Path $folder -PathType Container) { Remove-Item $folder -Force -Recurse } }
        
        Invoke-Command -ScriptBlock $deleteTempFolder -ArgumentList $tempFolder -Session $session -Verbose:$verbose

        $session | Disconnect-PSSession | Remove-PSSession
    }

    Trace-VstsLeavingInvocation $MyInvocation
}
