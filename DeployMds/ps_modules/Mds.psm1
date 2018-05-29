<############################################################################################ 
	Provide functions for Master Data Services.
############################################################################################>
function Get-Data {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)] [string]$databaseInstance,
        [Parameter(Position = 1, Mandatory = $true)] [string]$databaseName,
        [Parameter(Position = 2, Mandatory = $true)] [string]$query
    )
    BEGIN {
        Write-Verbose "Get-Data serverName = $databaseInstance, databaseName = $databaseName, query = $query"
    }
    PROCESS {
        try {
            # Init connection
            $connectionString = "Server=$databaseInstance;Database=$databaseName;Integrated Security=SSPI;Connection Timeout=3600"    
            $connection = New-Object System.Data.SqlClient.SQLConnection
            $connection.ConnectionString = $connectionString
            # Open connection
            $connection.Open()
            # Init command and data adapter
            $cmd = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
            $cmd.CommandTimeout = 3600                     # 60 min.
            $dt = New-Object System.Data.DataTable
            $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
            $da.SelectCommand.CommandTimeout = 3600        # 60 min.
            [void]$da.Fill($dt)
            # Return data
            return $dt
        }
        catch [Exception] {
            throw $_.Exception
        }
        finally {
            # Close and dispose
            if ($null -ne $cmd) {
                $cmd.Dispose()
            }
            if ($null -ne $connection) {
                $connection.Close()
                $connection.Dispose()
            }
        }
    }
    END { }
} 
function Invoke-Query {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)] [string]$databaseInstance,
        [Parameter(Position = 1, Mandatory = $true)] [string]$databaseName,
        [Parameter(Position = 2, Mandatory = $true)] [string]$query
    )
    BEGIN {
        Write-Verbose "Invoke-Query: databaseInstance = $databaseInstance, databaseName = $databaseName, query = $query"
    }
    PROCESS {
        try {
            # Init connection
            $connString = "Server=$databaseInstance;Database=$databaseName;Integrated Security=SSPI;Connection Timeout=3600"    
            $conn = New-Object System.Data.SqlClient.SQLConnection
            $conn.ConnectionString = $connString
   
            $conn.Open()

            # Init command and data adapter
            $cmd = New-Object System.Data.SqlClient.SqlCommand($query, $conn)
            $cmd.CommandTimeout = 3600 # 60 min.
            $cmd.ExecuteNonQuery()
        }
        catch [Exception] {
            throw $_.Exception
        }
        finally {
            # Close and dispose
            if ($null -ne $cmd) {
                $cmd.Dispose()
            }
            if ($null -ne $conn) {
                $conn.Close()
                $conn.Dispose()
            }
        }
    }
    END { }
}

function Set-Administrator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$databaseInstance,
        [Parameter(Mandatory = $true)] [string]$databaseName,
        [Parameter(Mandatory = $true)] [string]$sid,
        [Parameter(Mandatory = $true)] [string]$username,
        [Parameter(Mandatory = $false)] [string]$displayName = "",
        [Parameter(Mandatory = $false)] [string]$description = "",
        [Parameter(Mandatory = $false)] [string]$emailAddress = ""
    )
    BEGIN {
        Write-Verbose "Set-Administrator: databaseInstance = $databaseInstance, databaseName = $databaseName, sid = $sid, displayName = $displayName, description = $description, emailAddress = $emailAddress"
    }
    PROCESS {
        $sql = "EXEC [mdm].[udpSecuritySetAdministrator] @UserName='$username', @SID = '$sid', @DisplayName = '$displayName', @Description = '$description', @EmailAddress = '$emailAddress', @PromoteNonAdmin = 1"

        Invoke-Query $databaseInstance $databaseName $sql | Out-Null
    }
    END { }
} 

function Confirm-Model
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$databaseInstance,
        [Parameter(Mandatory = $true)] [string]$databaseName,
        [Parameter(Mandatory = $true)] [string]$SID,
        [Parameter(Mandatory = $true)] [string]$ModelName
    )
    BEGIN { }
    PROCESS {
        $sql = @"
        DECLARE @ModelName NVARCHAR(50) = $ModelName
        DECLARE @Model_Id INT
        DECLARE @SID NVARCHAR(50) = $SID
        DECLARE @User_Id INT
        DECLARE @Version_ID INT

        SET @User_Id = (SELECT ID FROM mdm.tbluser u WHERE u.SID = @SID)
        SET @Model_Id = (SELECT TOP 1 model_id FROM mdm.viw_system_schema_version WHERE Model_Name = @modelname)
        SET @Version_ID = (SELECT MAX(ID) FROM mdm.viw_system_schema_version WHERE Model_ID = @Model_Id)

        EXEC mdm.udpValidateModel @user_id, @Model_ID, @Version_ID, 1
"@

        Invoke-Query $databaseInstance $databaseName $sql | Out-Null
    }
    END { }
}

function Get-Administrator {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)] [string]$databaseInstance,
        [Parameter(Position = 1, Mandatory = $true)] [string]$databaseName
    )
    BEGIN {
        Write-Verbose "Get-Administrator: databaseInstance = $databaseInstance, databaseName = $databaseName"
    }
    PROCESS {
        $sql = "SELECT SID, UserName, DisplayName, Description, EmailAddress FROM mdm.tblUser WHERE ID = 1"
        $adminData = Get-Data $databaseInstance $databaseName $sql
        return $adminData
    }
    END { }
}

function New-TemporaryFolder
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession]$Session
    )
    BEGIN { }
    PROCESS
    {
        $createTempFolder = {
            $parent = [System.IO.Path]::GetTempPath()
            $name = [System.IO.Path]::GetRandomFileName()

            $dirPath = Join-Path $parent $name
            $folder =  New-Item -ItemType Directory -Path $dirPath

            return $folder.FullName
        }

        if ($Session)
        {
            $tempFolder = Invoke-Command -ScriptBlock $createTempFolder -Session $Session
        }
        else
        {
            $tempFolder = Invoke-Command -ScriptBlock $createTempFolder
        }

        return $tempFolder
    }
    END { }
}

function Publish-MdsPackages
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Packages,
        [Parameter(Mandatory = $true)][string]$MdsExecutable,
        [Parameter(Mandatory = $true)][string]$MdsServiceName,
        [ValidateSet("deployclone","deploynew","deployupdate","deployupdatedata")][Parameter(Mandatory = $true)]$MdsDeploymentType,
        [string]$ModelVersion,
        [string]$ModelName,
        [System.Management.Automation.Runspaces.PSSession]$Session
    )
    BEGIN { }
    PROCESS
    {
        $deployScript = {
            param
            (
                $packages,
                $mdsExecutable,
                $mdsServiceName,
                $mdsDeploymentType,
                $modelVersion,
                $mdsModelName
            )
    
            function exec
            {
                param
                (
                    [string] $Command,
                    [string[]] $Params,
                    [string] $StderrPrefix = "",
                    [int[]] $AllowedExitCodes = @(0)
                )
            
                $backupErrorActionPreference = $script:ErrorActionPreference
                $script:ErrorActionPreference = "Continue"
    
                try
                {
                    Write-Output ("##vso[task.debug]Running '$Command $($Params -join " ")'")
    
                    $output = & $Command $Params 2>&1
    
                    $output | ForEach-Object -Process `
                        {
                            if ($_ -like "*ERROR*")
                            {
                                throw ($output | Where-Object {$_ -ne ""} | Out-String)
                            }
                        }
    
                    $output | ForEach-Object -Process `
                        {
                            if ($_ -is [System.Management.Automation.ErrorRecord])
                            {
                                "$StderrPrefix$_"
                            }
                            else
                            {
                                "$_"
                            }
                        }
    
                    Write-Output "##vso[task.debug]Exit code is $LASTEXITCODE"
    
                    if ($AllowedExitCodes -notcontains $LASTEXITCODE)
                    {
                        throw "Execution failed with exit code $LASTEXITCODE"
                    }
                }
                finally
                {
                    $script:ErrorActionPreference = $backupErrorActionPreference
                }
            }
    
            $script:ErrorActionPreference = "Stop"
    
            foreach ($package in $packages)
            {
                if($mdsDeploymentType -eq "deployclone")
                {
                    $argList = @("deployclone", "-package", """$package""")
                }
    
                if($mdsDeploymentType -eq "deployupdatedata")
                {
                    $argList = @("deployupdate",  "-package", """$package""", "-version", """$modelVersion""")
                }
    
                if($mdsDeploymentType -eq "deployupdate")
                {
                    $argList = @("deployupdate", "-package", """$package""")
                }

                if($mdsDeploymentType -eq "deploynew")
                {
                    $argList = @("deploynew", "-package", """$package""", "-model", $mdsModelName)
                }

                if ($mdsServiceName)
                {
                    $argList += @("-service", """$mdsServiceName""")
                }
    
                exec $mdsExecutable $argList
            }
        }

        if ($Session)
        {
            Invoke-Command -ScriptBlock $deployScript -ArgumentList $Packages, $MdsExecutable, $MdsServiceName, $MdsDeploymentType, $ModelVersion, $ModelName -Session $Session
        }
        else
        {
            Invoke-Command -ScriptBlock $deployScript -ArgumentList $Packages, $MdsExecutable, $MdsServiceName, $MdsDeploymentType, $ModelVersion, $ModelName
        }
    }
    END { }
}

function Get-MdsPath
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession]$Session,
        [ValidateSet("90","100","110","120","130","140")][string][parameter(Mandatory = $true)]$SqlServerVersion
    )
    BEGIN { }
    PROCESS
    {
        $getMdsExe = {
            param
            (
                $sqlServerVersion
            )
            
            $item = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$sqlServerVersion\Master Data Services\InstallPath" -Name "MDSInstallPathx64"
            
            return $item.MDSInstallPathx64
        }
        
        if ($Session)
        {
            $MDSInstallPathx64 = Invoke-Command -ScriptBlock $getMdsExe -ArgumentList $SqlServerVersion -Session $Session
        }
        else
        {
            $MDSInstallPathx64 = Invoke-Command -ScriptBlock $getMdsExe -ArgumentList $SqlServerVersion
        }
        
        if (-not $MDSInstallPathx64)
        {
            throw "MDS for SQL $sqlServerVersion was not found"
        }
    
        return Join-Path $MDSInstallPathx64 "Master Data Services\Configuration\MDSModelDeploy.exe"
    }
    END { }
}

function Get-UserSid
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)] [string]$Username
    )
    BEGIN
    {
        Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
        Write-Verbose "Parameter Values"
        $PSBoundParameters.Keys | ForEach-Object { Write-Verbose "$_ = '$($PSBoundParameters[$_])'" }
    }
    PROCESS
    {
        if ($Username.Contains("\"))
        {
            $dl = $Username -split "\\"
        
            $domain = $dl[0]
            $user = $dl[1]

            $objUser = New-Object System.Security.Principal.NTAccount($domain, $user)
            $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier]) 
            
            return $strSID.Value
        }
        else
        {
            throw "Username not in down-level logon name format (DOMAIN\UserName)."
        }
    }
    END { }
}

function Resolve-HostNameOrAddress
{
    [CmdletBinding()]
    param
    (
        [Parameter(Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('HostName','IPAddress','CNAME','cn')]
        [string]$ComputerName = $env:COMPUTERNAME
    )
    BEGIN { Write-Verbose "Invoked Resolve-HostNameOrAddress with ComputerName = '$ComputerName'" }
    PROCESS
    { 
        if ([bool]($ComputerName -as [ipaddress]))
        {
            $host1 = [System.Net.Dns]::GetHostEntry($ComputerName)
        }
        else
        {
            $host1 = [System.Net.Dns]::GetHostByName($ComputerName)
        }

        return $host1.HostName
    }
    END {}
}