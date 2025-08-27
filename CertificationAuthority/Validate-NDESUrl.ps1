
<#

.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.

.SYNOPSIS
Validate-NDESUrl will check that requests from devices enrolled in Microsoft Intune will get through all the network protections (such as a reverse proxy) and make it to the NDES server.

.DESCRIPTION
Since the certificate requests include a payload query string that is longer than what is allowed by default settings in Windows, IIS and some reverse proxy servers, those servers need to be configured to allow long query strings and web requests.
This tool will simulate a SCEP request with a large payload, allowing you to check the IIS logs on the NDES server to ensure that the request is not being blocked anywhere along the way.

.NOTE

.EXAMPLE
Validate-NDESUrl

#>
[CmdletBinding(DefaultParameterSetName="NormalRun")]

Param(

    [parameter(Mandatory=$true,ParameterSetName="NormalRun")]
    [alias("s")]
    [ValidateScript({
    if (!($_.contains("/"))){

        $True

    }

    else {

    Throw "Please use the hostname FQDN and not the HTTPS URL. Example: 'scep-contoso.msappproxy.net'"

    }

    }
)]

    [string]$server,

    [parameter(Mandatory=$true,ParameterSetName="NormalRun")]
    [alias("q")]
    [ValidateRange(1,31)]
    [INT]$querysize,

    [parameter(ParameterSetName="Help")]
    [alias("h","?","/?")]
    [switch]$help,

    [parameter(ParameterSetName="Help")]
    [alias("u")]
    [switch]$usage
    )

#################################################################


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
            "DeviceManagementConfiguration.Read.All",
            "Group.Read.All"
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

function Show-Usage{

    Write-Host
    Write-Host "-help                       -h         Displays the help."
    Write-Host "-usage                      -u         Displays this usage information."
    Write-Host "-querysize                  -q         Specify the size of the query string payload to use as a number of kilobytes (i.e. 20 or 25). Maximum value is 31"
    Write-Host "-server                     -s         Specify NDES server public DNS name in the form FQDN. For example ExternalDNSName.Contoso.com"
    Write-Host

}

#################################################################

function Get-NDESURLHelp{

    write-host "Validate-NDESUrl will check that requests from devices enrolled in Microsoft Intune will get through all the network protections (such as a reverse proxy) and make it to the NDES server."
    Write-Host
    write-host "Since the certificate requests include a payload query string that is longer than what is allowed by default settings in Windows, IIS and some reverse proxy servers, those servers need to be configured to allow long query strings and web requests."
    write-host "This tool will simulate a SCEP request with a large payload, allowing you to check the IIS logs on the NDES server to ensure that the request is not being blocked anywhere along the way."
    Write-Host

}

#################################################################

    if($help){

    Get-NDESURLHelp

    break

    }

    if($usage){

        Show-Usage

        break
    }

#Requires -version 4.0
#Requires -RunAsAdministrator

#################################################################

#region Check if NDES is installed

    if ((Get-WmiObject -class Win32_OperatingSystem).ProductType -notlike "1"){

        if (Test-Path HKLM:SOFTWARE\Microsoft\Cryptography\MSCEP) {

        Write-Host
        Write-Host "Error: This appears to be the NDES server. Please run this script from a different machine. An external (guest) connection is best." -BackgroundColor Red
        write-host "Exiting......................"
        break

        }
    }

#endregion

#################################################################

#region Configuring base URI and ensuring it is in a fit state to proceed

Write-host
Write-host "......................................................."
Write-host
Write-Host "Trying base NDES URI... " -ForegroundColor Yellow
Write-host

    if (resolve-dnsname $server -ErrorAction SilentlyContinue){


    $NDESUrl = "https://$($server)/certsrv/mscep/mscep.dll"
    $BaseURLstatuscode = try {(Invoke-WebRequest -Uri $NDESUrl).statuscode} catch {$_.Exception.Response.StatusCode.Value__}

        if ($BaseURLstatuscode -eq "200"){

        Write-Warning "$($NDESUrl) returns a status code 200 . This usually signifies an error with the Intune Connector registering itself or not being installed."
        Write-Host
        Write-Host "This state will _not_ provide a working NDES infrastructure, although validation of long URI support can continue."
        Write-Host

        }


        elseif ($BaseURLstatuscode -eq "403"){

        Write-Host "Success: " -ForegroundColor Green -NoNewline
        write-host "Proceeding with validation!"

        }

        else {

        Write-Warning "Unexpected Error code! This usually signifies an error with the Intune Connector registering itself or not being installed."
        Write-Host
        Write-host "Expected value is a 403. We received a $($BaseURLstatuscode). This state will _not_ provide a working NDES infrastructure, although we can proceed with the validation included in this test"

        }

    }

    else {

    write-host "Error: Cannot resolve $($server)" -BackgroundColor Red
    Write-Host
    Write-Host "Please ensure a DNS record is in place and name resolution is successful"
    Write-Host
    Write-Host "Exiting................................................"
    Write-Host
    exit

    }




#endregion

#################################################################

#region Trying to retrieve CACaps...

Write-host
Write-host "......................................................."
Write-host
Write-Host "Trying to retrieve CA Capabilities... " -ForegroundColor Yellow
Write-host
$GetCACaps = "$($NDESUrl)?operation=GetCACaps&message=NDESLongUrlValidatorStep1of3"
$CACapsStatuscode = try {(Invoke-WebRequest -Uri $GetCACaps).statuscode} catch {$_.Exception.Response.StatusCode.Value__}

    if (-not ($CACapsStatuscode -eq "200")){

    Write-host "Retrieving the following URL: " -NoNewline
    Write-Host "$GetCACaps" -ForegroundColor Cyan
    Write-host
    write-host "Error: Server returned a $CACapsStatuscode error. " -BackgroundColor Red
    Write-Host
    write-host "For a list of IIS error codes, please visit the below link."
    Write-Host "URL: https://support.microsoft.com/en-gb/help/943891/the-http-status-code-in-iis-7-0--iis-7-5--and-iis-8-0"

    }

    else {

    Write-host "Retrieving the following URL: " -NoNewline
    Write-Host "$GetCACaps" -ForegroundColor Cyan
    Write-host

    $CACaps = (Invoke-WebRequest -Uri $GetCACaps).content

        if ($CACaps) {

        Write-Host "Success: " -ForegroundColor Green -NoNewline
        write-host "CA CApabilities retrieved:"
        Write-Host
        write-host $CACaps

        }

        else {

        write-host "Error: Server is not returning CA Capabilities." -BackgroundColor Red
        Write-Host
        write-host "PLEASE NOTE: This is not a long URI issue. Please investigate the NDES configuration."
        Write-Host

        }

}

#endregion

#################################################################

#region Trying to retrieve CACerts

Write-host
Write-host "......................................................."
Write-host
Write-Host "Trying to retrieve CA Certificates... " -ForegroundColor Yellow
Write-host

$GetCACerts = "$($NDESUrl)?operation=GetCACerts&message=NDESLongUrlValidatorStep2of3"
$CACertsStatuscode = try {(Invoke-WebRequest -Uri $GetCACerts).statuscode} catch {$_.Exception.Response.StatusCode.Value__}

    if (-not ($CACertsStatuscode -eq "200")){

    Write-host "Attempting to retrieve certificates from the following URL: " -NoNewline
    Write-Host "$GetCACerts" -ForegroundColor Cyan
    Write-host
    write-host "Error: Server returned a $CACertsStatuscode error. " -BackgroundColor Red
    Write-Host
    write-host "For a list of IIS error codes, please visit the below link."
    Write-Host "URL: https://support.microsoft.com/en-gb/help/943891/the-http-status-code-in-iis-7-0--iis-7-5--and-iis-8-0"

    }

    else {

    Write-host "Attempting to retrieve certificates from the following URI: " -NoNewline
    Write-Host "$GetCACerts" -ForegroundColor Cyan
    Write-Host

    $CACerts = (Invoke-WebRequest -Uri $GetCACerts).content

    if ($CACerts) {

        Invoke-WebRequest -Uri $GetCACerts -ContentType "application/x-x509-ca-ra-cert" -OutFile "$env:temp\$server.p7b"
        Write-Host "Success: " -ForegroundColor Green -NoNewline
        write-host "certificates retrieved. File written to disk: $env:temp\$server.p7b"

    }

    else {

        write-host "Error: Server is not returning CA certificates." -BackgroundColor Red
        Write-Host
        write-host "PLEASE NOTE: This is _not_ a long URI issue. Please investigate the NDES configuration."
        Write-Host

    }

}

#endregion

#################################################################

#region SCEP Challenge

Write-host
Write-host "......................................................."
Write-host
Write-Host "Querying URI with simulated SCEP challenge... " -ForegroundColor Yellow
Write-host
$ChallengeUrlTemp = "$($NDESUrl)?operation=PKIOperation&message=<SCEP CHALLENGE STRING>"
Write-host "Retrieving the following URI: " -NoNewline
Write-Host "$ChallengeUrlTemp" -ForegroundColor Cyan
Write-host
Write-Host "Using a query size of $($querysize)KB... "
Write-Host
$challengeBase = "NDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallengeNDESLongUrlValidatorFakeChallenge";
$testChallenge = $null

    for ($i=1; $i -le $querySize; $i++){

        $testChallenge += $challengeBase + ($i + 1)

    }

$LongUrl = "$($NDESUrl)?operation=PKIOperation&message=$($testChallenge)"
$LongUrlStatusCode = try {(Invoke-WebRequest -Uri $LongUrl).statuscode} catch {$_.Exception.Response.StatusCode.Value__}

    if ($LongUrlStatusCode -eq "414"){

        write-host "Error: HTTP Error 414. The $($querysize)KB URI is too long. " -BackgroundColor Red
        Write-Host
        Write-Host "Please ensure all servers and network devices support long URI's" -ForegroundColor Blue
        write-host

    }

    elseif (-not ($LongUrlStatusCode -eq "200")) {

        write-host "Error: HTTP Error $($LongUrlStatusCode)" -BackgroundColor Red
        Write-Host
        Write-Host "Please check your network configuration." -ForegroundColor Blue -BackgroundColor white
        write-host
        write-host "For a list of IIS error codes, please visit the below link."
        Write-Host "URL: https://support.microsoft.com/en-gb/help/943891/the-http-status-code-in-iis-7-0--iis-7-5--and-iis-8-0"

    }

    else {

        Write-Host "Success: " -ForegroundColor Green -NoNewline
        write-host "Server accepts a $($querysize)KB URI."

     }

#endregion

#################################################################

#region Ending script

Write-host
Write-host "......................................................."
Write-host
Write-host "End of NDES URI validation" -ForegroundColor Yellow
Write-Host
write-host "Ending script..." -ForegroundColor Yellow
Write-host

#endregion

