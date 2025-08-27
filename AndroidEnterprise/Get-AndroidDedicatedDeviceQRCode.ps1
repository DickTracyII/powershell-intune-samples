
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
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementServiceConfig.Read.All"
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

Function Get-AndroidEnrollmentProfile {

<#
.SYNOPSIS
Gets Android Enterprise Enrollment Profile
.DESCRIPTION
Gets Android Enterprise Enrollment Profile
.EXAMPLE
Get-AndroidEnrollmentProfile
.NOTES
NAME: Get-AndroidEnrollmentProfile
#>

$graphApiVersion = "Beta"
$Resource = "deviceManagement/androidDeviceOwnerEnrollmentProfiles"

    try {

        $now = (Get-Date -Format s)
        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)?`$filter=tokenExpirationDateTime gt $($now)z"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).value

    }

    catch {

    $ex = $_.Exception
    $errorResponse = $ex.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    Write-Host "Response content:`n$responseBody" -f Red
    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    write-host
    break

    }

}

####################################################

Function Get-AndroidQRCode{

<#
.SYNOPSIS
Gets Android Device Owner Enrollment Profile QRCode Image
.DESCRIPTION
Gets Android Device Owner Enrollment Profile QRCode Image
.EXAMPLE
Get-AndroidQRCode
.NOTES
NAME: Get-AndroidQRCode
#>

[cmdletbinding()]

Param(
[parameter(Mandatory=$true)]
[string]$Profileid
)

$graphApiVersion = "Beta"

    try {

        $Resource = "deviceManagement/androidDeviceOwnerEnrollmentProfiles/$($Profileid)?`$select=qrCodeImage"
        $uri = "$global:GraphEndpoint/$graphApiVersion/$Resource"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get)

    }

    catch {

    $ex = $_.Exception
    $errorResponse = $ex.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    Write-Host "Response content:`n$responseBody" -f Red
    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    write-host
    break

    }

}

####################################################

#region Authentication

# Connect to Microsoft Graph
if (-not (Connect-GraphAPI)) {
    Write-Error "Failed to connect to Microsoft Graph. Exiting script."
    exit 1
}

#endregion

####################################################

$parent = [System.IO.Path]::GetTempPath()
[string] $name = [System.Guid]::NewGuid()
New-Item -ItemType Directory -Path (Join-Path $parent $name) | Out-Null
$TempDirPath = "$parent$name"

####################################################

$Profiles = Get-AndroidEnrollmentProfile

if($profiles){

$profilecount = @($profiles).count

    if(@($profiles).count -gt 1){

    Write-Host "Corporate-owned dedicated device profiles found: $profilecount"
    Write-Host

    $COSUprofiles = $profiles.Displayname | Sort-Object -Unique

    $menu = @{}

    for ($i=1;$i -le $COSUprofiles.count; $i++)
    { Write-Host "$i. $($COSUprofiles[$i-1])"
    $menu.Add($i,($COSUprofiles[$i-1]))}

    Write-Host
    $ans = Read-Host 'Choose a profile (numerical value)'

    if("" -eq $ans -or $null -eq $ans){

        Write-Host "Corporate-owned dedicated device profile can't be null, please specify a valid Profile..." -ForegroundColor Red
        Write-Host
        break

    }

    elseif(($ans -match "^[\d\.]+$") -eq $true){

    $selection = $menu.Item([int]$ans)

    Write-Host

        if($selection){

            $SelectedProfile = $profiles | ? { $_.DisplayName -eq "$Selection" }

            $SelectedProfileID = $SelectedProfile | select -ExpandProperty id

            $ProfileID = $SelectedProfileID

            $ProfileDisplayName = $SelectedProfile.displayName

        }

        else {

            Write-Host "Corporate-owned dedicated device profile selection invalid, please specify a valid Profile..." -ForegroundColor Red
            Write-Host
            break

        }

    }

    else {

        Write-Host "Corporate-owned dedicated device profile selection invalid, please specify a valid Profile..." -ForegroundColor Red
        Write-Host
        break

    }

}

    elseif(@($profiles).count -eq 1){

        $Profileid = (Get-AndroidEnrollmentProfile).id
        $ProfileDisplayName = (Get-AndroidEnrollmentProfile).displayname

        Write-Host "Found a Corporate-owned dedicated devices profile '$ProfileDisplayName'..."
        Write-Host

    }

    else {

        Write-Host
        write-host "No enrollment profiles found!" -f Yellow
        break

    }

Write-Warning "You are about to export the QR code for the Dedicated Device Enrollment Profile '$ProfileDisplayName'"
Write-Warning "Anyone with this QR code can Enrol a device into your tenant. Please ensure it is kept secure."
Write-Warning "If you accidentally share the QR code, you can immediately expire it in the Intune UI."
write-warning "Devices already enrolled will be unaffected."
Write-Host
Write-Host "Show token? [Y]es, [N]o"

$FinalConfirmation = Read-Host

    if ($FinalConfirmation -ne "y"){

        Write-Host "Exiting..."
        Write-Host
        break

    }

    else {

    Write-Host

    $QR = (Get-AndroidQRCode -Profileid $ProfileID)

    $QRType = $QR.qrCodeImage.type
    $QRValue = $QR.qrCodeImage.value

    $imageType = $QRType.split("/")[1]

    $filename = "$TempDirPath\$ProfileDisplayName.$imageType"

    $bytes = [Convert]::FromBase64String($QRValue)
    [IO.File]::WriteAllBytes($filename, $bytes)

        if (Test-Path $filename){

            Write-Host "Success: " -NoNewline -ForegroundColor Green
            write-host "QR code exported to " -NoNewline
            Write-Host "$filename" -ForegroundColor Yellow
            Write-Host

        }

        else {

            write-host "Oops! Something went wrong!" -ForegroundColor Red

        }

    }

}

else {

    Write-Host "No Corporate-owned dedicated device Profiles found..." -ForegroundColor Yellow
    Write-Host

}

