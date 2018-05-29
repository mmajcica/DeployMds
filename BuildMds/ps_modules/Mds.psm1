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

function Join-String
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$String,
        [Parameter(Position = 1)][string]$Delimiter = ""
    )
    BEGIN {$items = @() }
    PROCESS { $items += $String }
    END { return ($items -join $Delimiter) }
}

<############################################################################################ 
	Retrieves the server, username and password from the specified generic endpoint.
############################################################################################>
function Get-EndpointData()
{
	[CmdletBinding()]
	param
	(
		[string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$ConnectedServiceName
	)
	BEGIN
	{
		Write-Verbose "ConnectedServiceName = $ConnectedServiceName"
	}
	PROCESS
	{
		$serviceEndpoint = Get-VstsEndpoint -Name $ConnectedServiceName -Require
        $endpoint = @{}

		if (!$serviceEndpoint)
		{
			throw "A Connected Service with name '$ConnectedServiceName' could not be found.  Ensure that this Connected Service was successfully provisioned using the services tab in the Admin UI."
		}

		$authScheme = $serviceEndpoint.Auth.Scheme
		if ($authScheme -ne 'UserNamePassword')
		{
			throw "The authorization scheme $authScheme is not supported by server endpoints."
		}

        if ($serviceEndpoint.Auth.Parameters.UserName)
        {
            $endpoint.Username = $serviceEndpoint.Auth.Parameters.UserName;
        }
        else
        {
            throw "Endpoint username value not specified."
        }

        if ($serviceEndpoint.Auth.Parameters.Password)
        {
            $type = $serviceEndpoint.Auth.Parameters.Password.GetType()
            Write-Verbose "Password field type $type"

            $endpoint.Password = $serviceEndpoint.Auth.Parameters.Password;
        }
        else
        {
            $endpoint.Password = New-Object System.Security.SecureString	
        }

		$securePassword = ConvertTo-SecureString -String $endpoint.Password -asPlainText -Force
        $endpoint.Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $endpoint.Username, $securePassword

        if ($serviceEndpoint.Url)
        {
            $server = ([Uri]($serviceEndpoint.Url)).AbsoluteUri.TrimEnd('/')

            if (-not $server.EndsWith(".eu.rabodev.com", "InvariantCultureIgnoreCase"))
            {
                $server = "$server.eu.rabodev.com"
            }

            if ($server.StartsWith("http", "InvariantCultureIgnoreCase"))
            {
                $server = $server.TrimStart('http://')
            }

            $endpoint.Server = $server
            $endpoint.OriginalServer = $serviceEndpoint.Url
        }
        else
        {
            #this can't never be the case as the Url filed is mandatory
            throw "Endpoint Url is not specified in the Endpoint configuration."
        }

        Write-Verbose "Endpoint Url: $($endpoint.Url)"
        Write-Verbose "Endpoint OriginalUrl: $($endpoint.OriginalUrl)"
        Write-Verbose "Endpoint Username: $($endpoint.Username)"

		return $endpoint
	}
	END { }
}