<#

.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.

#>


function Connect-GraphAPI {
<#
.SYNOPSIS
Connects to Microsoft Graph API with appropriate scopes for Intune operations
.DESCRIPTION
This function connects to Microsoft Graph using the Microsoft.Graph.Authentication module
.PARAMETER Scopes
Array of permission scopes required for the operations
.PARAMETER Environment
The Microsoft Graph environment to connect to (Global, USGov, USGovDod, China, Germany)
.EXAMPLE
Connect-GraphAPI
Connects to Microsoft Graph with default scopes
.EXAMPLE
Connect-GraphAPI -Environment "USGov"
Connects to Microsoft Graph US Government environment
.NOTES
Requires Microsoft.Graph.Authentication module
#>
    [CmdletBinding()]
    param(
        [string[]]$Scopes = @(
            "DeviceManagementApps.Read.All"
        ),
        [ValidateSet("Global", "USGov", "USGovDod", "China", "Germany")]
        [string]$Environment = "Global"
    )

    try {
        # Set global Graph endpoint based on environment
        switch ($Environment) {
            "Global" { $global:GraphEndpoint = "https://graph.microsoft.com" }
            "USGov" { $global:GraphEndpoint = "https://graph.microsoft.us" }
            "USGovDod" { $global:GraphEndpoint = "https://dod-graph.microsoft.us" }
            "China" { $global:GraphEndpoint = "https://microsoftgraph.chinacloudapi.cn" }
            "Germany" { $global:GraphEndpoint = "https://graph.microsoft.de" }
            default { $global:GraphEndpoint = "https://graph.microsoft.com" }
        }

        Write-Host "Graph Endpoint: $global:GraphEndpoint" -ForegroundColor Magenta
        # Check if Microsoft.Graph.Authentication module is available
        if (-not (Get-Module -Name Microsoft.Graph.Authentication -ListAvailable)) {
            Write-Error "Microsoft.Graph.Authentication module not found. Please install it using: Install-Module Microsoft.Graph.Authentication"
            return $false
        }

        # Import the module if not already loaded
        if (-not (Get-Module -Name Microsoft.Graph.Authentication)) {
            Import-Module Microsoft.Graph.Authentication -Force
        }

        # Connect to Microsoft Graph
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
        Connect-MgGraph -Scopes $Scopes -Environment $Environment -NoWelcome

        # Verify connection
        $context = Get-MgContext
        if ($context) {
            Write-Host "Successfully connected to Microsoft Graph!" -ForegroundColor Green
            Write-Host "Tenant ID: $($context.TenantId)" -ForegroundColor Yellow
            Write-Host "Account: $($context.Account)" -ForegroundColor Yellow
            Write-Host "Environment: $($context.Environment)" -ForegroundColor Yellow
            Write-Host "Scopes: $($context.Scopes -join ', ')" -ForegroundColor Yellow
            return $true
        }
        else {
            Write-Error "Failed to establish connection to Microsoft Graph"
            return $false
        }
    }
    catch {
        Write-Error "Error connecting to Microsoft Graph: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-IntuneRestMethod {
<#
.SYNOPSIS
Invokes Microsoft Graph REST API calls with automatic paging support
.DESCRIPTION
This function makes REST API calls to Microsoft Graph with built-in error handling and automatic paging for large result sets
.PARAMETER Uri
The Microsoft Graph URI to call (can be relative path or full URL)
.PARAMETER Method
The HTTP method to use (GET, POST, PUT, DELETE, PATCH)
.PARAMETER Body
The request body for POST/PUT/PATCH operations
.PARAMETER ContentType
The content type for the request (default: application/json)
.EXAMPLE
Invoke-IntuneRestMethod -Uri "v1.0/deviceManagement/deviceConfigurations" -Method GET
.EXAMPLE
Invoke-IntuneRestMethod -Uri "v1.0/deviceManagement/deviceConfigurations" -Method GET
.NOTES
Requires an active Microsoft Graph connection via Connect-MgGraph
Uses the global $GraphEndpoint variable for environment-specific endpoints
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [object]$Body = $null,

        [Parameter(Mandatory = $false)]
        [string]$ContentType = 'application/json'
    )

    try {
        # Ensure we have a Graph endpoint set
        if (-not $global:GraphEndpoint) {
            $global:GraphEndpoint = "https://graph.microsoft.com"
            Write-Warning "No Graph endpoint set, defaulting to: $global:GraphEndpoint"
        }

        # Handle both relative and absolute URIs
        if (-not $Uri.StartsWith("http")) {
            $Uri = "$global:GraphEndpoint/$Uri"
        }

        $results = @()
        $nextLink = $Uri

        do {
            Write-Verbose "Making request to: $nextLink"

            $requestParams = @{
                Uri = $nextLink
                Method = $Method
                ContentType = $ContentType
            }

            if ($Body) {
                if ($Body -is [string]) {
                    # Check if the string is valid JSON by trying to parse it
                    try {
                        $null = $Body | ConvertFrom-Json -ErrorAction Stop
                        # If we get here, it's valid JSON - use as-is
                        $requestParams.Body = $Body
                        Write-Verbose "Body detected as JSON string"
                    }
                    catch {
                        # String is not valid JSON, treat as plain string and wrap in quotes
                        $requestParams.Body = "`"$($Body)`""
                        Write-Verbose "Body detected as plain string, wrapping in quotes"
                    }
                } else {
                    # Body is an object (hashtable, PSCustomObject, etc.), convert to JSON
                    $requestParams.Body = $Body | ConvertTo-Json -Depth 10
                    Write-Verbose "Body detected as object, converting to JSON"
                }
            }

            $response = Invoke-MgGraphRequest @requestParams

            # Handle paging
            if ($response.value) {
                $results += $response.value
                $nextLink = $response.'@odata.nextLink'
            }
            else {
                $results += $response
                $nextLink = $null
            }

        } while ($nextLink)

        return $results
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Error "Graph API request failed with status $statusCode : $errorMessage"
        }
        else {
            Write-Error "Graph API request failed: $errorMessage"
        }
        throw
    }
}

####################################################

####################################################


    ####################################################

    function Get-ManagedAppPolicyRegistrationSummary {

    <#
    .SYNOPSIS
    This function is used to download App Protection Report for iOS and Android.
    .DESCRIPTION
    The function connects to the Graph API Interface and gets the ManagedAppRegistrationSummary
    .EXAMPLE
    Get-ManagedAppPolicyRegistrationSummary -ReportType Android_iOS
    Returns any managed app policies configured in Intune
    .NOTES
    NAME: Get-ManagedAppPolicyRegistrationSummary
    #>

        [cmdletbinding()]

        param
        (
            [ValidateSet("Android_iOS", "WIP_WE", "WIP_MDM")]
            $ReportType,
            $NextPage
        )

        $graphApiVersion = "Beta"
        $Stoploop = $false
        [int]$Retrycount = "0"
        do{
        try {

            if ("" -eq $ReportType -or $null -eq $ReportType) {
                $ReportType = "Android_iOS"

            }
            elseif ($ReportType -eq "Android_iOS") {

                $Resource = "/deviceAppManagement/managedAppStatuses('appregistrationsummary')?fetch=6000&policyMode=0&columns=DisplayName,UserEmail,ApplicationName,ApplicationInstanceId,ApplicationVersion,DeviceName,DeviceType,DeviceManufacturer,DeviceModel,AndroidPatchVersion,AzureADDeviceId,MDMDeviceID,Platform,PlatformVersion,ManagementLevel,PolicyName,LastCheckInDate"
                if ("" -ne $NextPage -and $null -ne $NextPage) {
                    $Resource += "&seek=$NextPage"
                }
                $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
                Invoke-IntuneRestMethod -Uri $uri -Method GET

            }

            elseif ($ReportType -eq "WIP_WE") {

                $Resource = "deviceAppManagement/managedAppStatuses('windowsprotectionreport')"
                if ("" -ne $NextPage -and $null -ne $NextPage) {
                    $Resource += "&seek=$NextPage"
                }
                $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
                Invoke-IntuneRestMethod -Uri $uri -Method GET

            }

            elseif ($ReportType -eq "WIP_MDM") {

                $Resource = "deviceAppManagement/mdmWindowsInformationProtectionPolicies"

                $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
                Invoke-IntuneRestMethod -Uri $uri -Method GET

            }
            $Stoploop = $true
        }

        catch {

            $ex = $_.Exception

            # Retry 4 times if 503 service time out
            if($ex.Response.StatusCode.value__ -eq "503") {
                $Retrycount = $Retrycount + 1
                $Stoploop = $Retrycount -gt 3
                if($Stoploop -eq $false) {
                    Start-Sleep -Seconds 5
                    continue
                }
            }
            $errorResponse = $ex.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorResponse)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $responseBody = $reader.ReadToEnd();
            Write-Host "Response content:`n$responseBody" -f Red
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
            write-host
            $Stoploop = $true
            break
        }
    }
    while ($Stoploop -eq $false)

    }

    ####################################################

    function Test-AuthToken {

        # Checking if authToken exists before running authentication
        if ($global:authToken) {

            # Setting DateTime to Universal time to work in all timezones
            $DateTime = (Get-Date).ToUniversalTime()

            # If the authToken exists checking when it expires
            $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes

            if ($TokenExpires -le 0) {

                write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow
                write-host

                # Defining User Principal Name if not present

                if ($null -eq $User -or "" -eq $User) {

                    $global:User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
                    Write-Host

                }

                $global:authToken = Connect-GraphAPIr $User

            }
        }

        # Authentication doesn't exist, calling Connect-GraphAPInction

        else {

            if ($null -eq $User -or "" -eq $User) {

                $global:User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
                Write-Host

            }

            # Getting the authorization token
            $global:authToken = Connect-GraphAPIr $User

        }
    }

    ####################################################

    Test-AuthToken

    ####################################################

    Write-Host

    $ExportPath = Read-Host -Prompt "Please specify a path to export the policy data to e.g. C:\IntuneOutput"

    # If the directory path doesn't exist prompt user to create the directory

    if (!(Test-Path "$ExportPath")) {

        Write-Host
        Write-Host "Path '$ExportPath' doesn't exist, do you want to create this directory? Y or N?" -ForegroundColor Yellow

        $Confirm = read-host

        if ($Confirm -eq "y" -or $Confirm -eq "Y") {

            new-item -ItemType Directory -Path "$ExportPath" | Out-Null
            Write-Host

        }

        else {

            Write-Host "Creation of directory path was cancelled..." -ForegroundColor Red
            Write-Host
            break

        }

    }

    Write-Host

    ####################################################

    $AppType = Read-Host -Prompt "Please specify the type of report [Android_iOS, WIP_WE, WIP_MDM]"

    if($AppType -eq "Android_iOS" -or $AppType -eq "WIP_WE" -or $AppType -eq "WIP_MDM") {

        Write-Host
        write-host "Running query against Microsoft Graph to download App Protection Report for '$AppType'.." -f Yellow

        $ofs = ','
        $stream = [System.IO.StreamWriter]::new("$ExportPath\AppRegistrationSummary_$AppType.csv", $false, [System.Text.Encoding]::UTF8)
        $ManagedAppPolicies = Get-ManagedAppPolicyRegistrationSummary -ReportType $AppType
        $stream.WriteLine([string]($ManagedAppPolicies.content.header | % {$_.columnName } ))

        do {
            Test-AuthToken

            write-host "Your data is being downloaded for '$AppType'..."
            $MoreItem = $ManagedAppPolicies.content.skipToken -ne "" -and $ManagedAppPolicies.content.skipToken -ne $null

            foreach ($SummaryItem in $ManagedAppPolicies.content.body) {

                $stream.WriteLine([string]($SummaryItem.values -replace ",","."))
            }

            if ($MoreItem){

                $ManagedAppPolicies = Get-ManagedAppPolicyRegistrationSummary -ReportType $AppType -NextPage ($ManagedAppPolicies.content.skipToken)
            }

        } while ($MoreItem)

        $stream.close()

        write-host

    }

    else {

        Write-Host "AppType isn't a valid option..." -ForegroundColor Red
        Write-Host

    }

