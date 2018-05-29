[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation
try
{
    [string]$connectedServiceName = Get-VstsInput -Name connectedServiceName -Require
    [string]$mdsService = Get-VstsInput -Name mdsService -Require
    [string]$mdsDatabaseInstance = Get-VstsInput -Name mdsDatabaseInstance -Require
    [string]$mdsDatabase = Get-VstsInput -Name mdsDatabase -Require
    [string]$mdsModels = Get-VstsInput -Name mdsModels -Require
    [bool]$mdsWithData = Get-VstsInput -Name mdsWithData -Default $false -AsBool
    [string]$sqlServerVersion = Get-VstsInput -Name ssVersion
    [string]$targetFolder = Get-VstsInput -Name targetFolder

    Import-Module -Name $PSScriptRoot\ps_modules\Mds.psm1 -Force
	
    # Verify output folder
    if ($targetFolder)
    {
        # if folder doesn't exist or it's not valid
        if (-not (Test-Path $targetFolder -PathType Container -IsValid))
        {
            throw "Provided target folder is not a valid path."
        }
    }
    else
    {
        $targetFolder = $env:BUILD_STAGINGDIRECTORY
    }

    # Get endpoint which hosts the MDS Master environment
    $endpoint = Get-EndpointData $connectedServiceName
    $session = New-PSSession -ComputerName $endpoint.Server -Credential $endpoint.Credential
    $sid = Get-UserSid($endpoint.Username)

    $mds = Get-MdsPath -Session $session -SqlServerVersion $sqlServerVersion
    $tempFolder = New-TemporaryFolder -Session $session

    # Construct package name
    $packageSuffix = "_NoData.pkg"
    if ($mdsWithData)
    {
        $packageSuffix = "_Data.pkg"
    }

    if ($sqlServerVersion -eq "110" -or $sqlServerVersion -eq "120")
    {
        # Get the current MDS Administrator
        $oldAdmin = Get-Administrator -databaseInstance $mdsDatabaseInstance -databaseName $mdsDatabase
        Write-Verbose "Current MDS admin is '$($oldAdmin.UserName)'."

        Set-Administrator -databaseInstance $mdsDatabaseInstance -databaseName $mdsDatabase -sid $sid -username $mdsUsername
        Write-Output "MDS admin is set to '$mdsUsername'."
    }

    # Iterate the list of models to be packaged
    $models = $mdsModels -Split ','
    foreach ($model in $models)
    {
        $fileName = $model + $packageSuffix
        # Generate a package and store it in the temp folder
        Write-Output "Generating package for $model..."
        $outputFile = Join-Path $tempFolder $fileName

        Invoke-Command -ArgumentList $mds, $model, $outputFile, $mdsService -Session $session -ScriptBlock { 
            param($mds, $model, $outputFile, $mdsService) 
            & $mds createpackage -service $mdsService -model $model -package $outputFile 
            }
            
        # Verify a package has been generated
        if (Invoke-Command -ScriptBlock { param($outputFile) Test-Path $outputFile } -ArgumentList $outputFile -Session $session)
        {
            # Verify target folder where the artifact should be copied to
            if (!(Test-Path $targetFolder))
            {
                New-Item $targetFolder -ItemType Directory -Force | Out-Null
            }

            # Copy the artifact to the target folder 
            Write-Output "Copy package to target folder $targetFolder"
            $artifactFile = Join-Path $targetFolder $fileName

            Copy-Item -Path $outputFile -Destination $artifactFile -Force -FromSession $session
        }
        else
        {
            throw "Model $model has not been generated"
        }
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