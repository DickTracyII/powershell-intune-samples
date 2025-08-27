
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
            "DeviceManagementApps.ReadWrite.All",
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

####################################################


####################################################

function Get-itunesApplication {

    <#
    .SYNOPSIS
    This function is used to get an iOS application from the itunes store using the Apple REST API interface
    .DESCRIPTION
    The function connects to the Apple REST API Interface and returns applications from the itunes store
    .EXAMPLE
    Get-itunesApplication -SearchString "Microsoft Corporation"
    Gets an iOS application from itunes store
    .EXAMPLE
    Get-itunesApplication -SearchString "Microsoft Corporation" -Limit 10
    Gets an iOS application from itunes store with a limit of 10 results
    .NOTES
    NAME: Get-itunesApplication
    https://affiliate.itunes.apple.com/resources/documentation/itunes-store-web-service-search-api/
    #>

    [cmdletbinding()]

    param
    (
        [Parameter(Mandatory=$true)]
        $SearchString,
        [int]$Limit
    )

        try{

        Write-Verbose $SearchString

        # Testing if string contains a space and replacing it with %20
        $SearchString = $SearchString.replace(" ","%20")

        Write-Verbose "SearchString variable converted if there is a space in the name $SearchString"

            if($Limit){

            $iTunesUrl = "https://itunes.apple.com/search?country=us&media=software&entity=software,iPadSoftware&term=$SearchString&limit=$limit"

            }

            else {

            $iTunesUrl = "https://itunes.apple.com/search?country=us&entity=software&term=$SearchString&attribute=softwareDeveloper"

            }

        write-verbose $iTunesUrl

        $apps = Invoke-RestMethod -Uri $iTunesUrl -Method Get

        # Putting sleep in so that no more than 20 API calls to itunes REST API
        # https://affiliate.itunes.apple.com/resources/documentation/itunes-store-web-service-search-api/
        Start-Sleep 3

        return $apps

        }

        catch {

        write-host $_.Exception.Message -f Red
        write-host $_.Exception.ItemName -f Red
        write-verbose $_.Exception
        write-host
        break

        }

    }

####################################################

function Add-iOSApplication {

    <#
    .SYNOPSIS
    This function is used to add an iOS application using the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and adds an iOS application from the itunes store
    .EXAMPLE
    Add-iOSApplication -AuthHeader $AuthHeader
    Adds an iOS application into Intune from itunes store
    .NOTES
    NAME: Add-iOSApplication
    #>

    [cmdletbinding()]

    param
    (
        $itunesApp
    )

    $graphApiVersion = "Beta"
    $Resource = "deviceAppManagement/mobileApps"

        try {

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"

        $app = $itunesApp

        Write-Verbose $app

        Write-Host "Publishing $($app.trackName)" -f Yellow

        # Step 1 - Downloading the icon for the application
        $iconUrl = $app.artworkUrl60

            if ($null -eq $iconUrl){

            Write-Host "60x60 icon not found, using 100x100 icon"
            $iconUrl = $app.artworkUrl100

            }

            if ($null -eq $iconUrl){

            Write-Host "60x60 icon not found, using 512x512 icon"
            $iconUrl = $app.artworkUrl512

            }

        $iconResponse = Invoke-WebRequest $iconUrl
        $base64icon = [System.Convert]::ToBase64String($iconResponse.Content)
        $iconType = $iconResponse.Headers["Content-Type"]

            if(($app.minimumOsVersion.Split(".")).Count -gt 2){

            $Split = $app.minimumOsVersion.Split(".")

            $MOV = $Split[0] + "." + $Split[1]

            $osVersion = [Convert]::ToDouble($MOV)

            }

            else {

            $osVersion = [Convert]::ToDouble($app.minimumOsVersion)

            }

        # Setting support Operating System Devices
        if($app.supportedDevices -match "iPadMini"){ $iPad = $true } else { $iPad = $false }
        if($app.supportedDevices -match "iPhone6"){ $iPhone = $true } else { $iPhone = $false }

        # Step 2 - Create the Hashtable Object of the application
        $description = $app.description -replace "[^\x00-\x7F]+",""

        $graphApp = @{
            "@odata.type"="#microsoft.graph.iosStoreApp";
            displayName=$app.trackName;
            publisher=$app.artistName;
            description=$description;
            largeIcon= @{
                type=$iconType;
                value=$base64icon;
            };
            isFeatured=$false;
            appStoreUrl=$app.trackViewUrl;
            applicableDeviceType=@{
                iPad=$iPad;
                iPhoneAndIPod=$iPhone;
            };
            minimumSupportedOperatingSystem=@{
                v8_0=$osVersion -lt 9.0;
                v9_0=$osVersion.ToString().StartsWith(9)
                v10_0=$osVersion.ToString().StartsWith(10)
                v11_0=$osVersion.ToString().StartsWith(11)
                v12_0=$osVersion.ToString().StartsWith(12)
                v13_0=$osVersion.ToString().StartsWith(13)
            };
        };

        # Step 3 - Publish the application to Graph
        Write-Host "Creating application via Graph"
        $createResult = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body (ConvertTo-Json $graphApp) -Headers $authToken
        Write-Host "Application created as $uri/$($createResult.id)"
        write-host

        }

        catch {

        $ex = $_.Exception
        Write-Host "Request to $Uri failed with HTTP Status $([int]$ex.Response.StatusCode) $($ex.Response.StatusDescription)" -f Red

        $errorResponse = $ex.Response.GetResponseStream()

        $ex.Response.GetResponseStream()

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

function Add-ApplicationAssignment {

<#
.SYNOPSIS
This function is used to add an application assignment using the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and adds a application assignment
.EXAMPLE
Add-ApplicationAssignment -ApplicationId $ApplicationId -TargetGroupId $TargetGroupId -InstallIntent $InstallIntent
Adds an application assignment in Intune
.NOTES
NAME: Add-ApplicationAssignment
#>

[cmdletbinding()]

param
(
    $ApplicationId,
    $TargetGroupId,
    $InstallIntent
)

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/mobileApps/$ApplicationId/assign"

    try {

        if(!$ApplicationId){

        write-host "No Application Id specified, specify a valid Application Id" -f Red
        break

        }

        if(!$TargetGroupId){

        write-host "No Target Group Id specified, specify a valid Target Group Id" -f Red
        break

        }


        if(!$InstallIntent){

        write-host "No Install Intent specified, specify a valid Install Intent - available, notApplicable, required, uninstall, availableWithoutEnrollment" -f Red
        break

        }

$JSON = @"

{
    "mobileAppAssignments": [
    {
        "@odata.type": "#microsoft.graph.mobileAppAssignment",
        "target": {
        "@odata.type": "#microsoft.graph.groupAssignmentTarget",
        "groupId": "$TargetGroupId"
        },
        "intent": "$InstallIntent"
    }
    ]
}

"@

    $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
    Invoke-IntuneRestMethod -Uri $uri -Method POST -Body $JSON

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

function Get-AADGroup {

<#
.SYNOPSIS
This function is used to get AAD Groups from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any Groups registered with AAD
.EXAMPLE
Get-AADGroup
Returns all users registered with Azure AD
.NOTES
NAME: Get-AADGroup
#>

[cmdletbinding()]

param
(
    $GroupName,
    $id,
    [switch]$Members
)

# Defining Variables
$graphApiVersion = "v1.0"
$Group_resource = "groups"

    try {

        if($id){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Group_resource)?`$filter=id eq '$id'"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value

        }

        elseif("" -eq $GroupName -or $null -eq $GroupName){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Group_resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value

        }

        else {

            if(!$Members){

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
            (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value

            }

            elseif($Members){

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
            $Group = (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value

                if($Group){

                $GID = $Group.id

                $Group.displayName
                write-host

                $uri = "$global:GraphEndpoint/$graphApiVersion/$($Group_resource)/$GID/Members"
                (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value

                }

            }

        }

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

# Setting application AAD Group to assign application

Write-Host
Write-Warning "This script adds all your iOS Store Apps as 'available' assignments for the Azure AD group you specify."
Write-Host
$AADGroup = Read-Host -Prompt "Enter the Azure AD Group name where applications will be assigned"

$TargetGroupId = (get-AADGroup -GroupName "$AADGroup").id

    if($null -eq $TargetGroupId -or "" -eq $TargetGroupId){

    Write-Host "AAD Group - '$AADGroup' doesn't exist, please specify a valid AAD Group..." -ForegroundColor Red
    Write-Host
    exit

    }

Write-Host

####################################################

# Set parameter culture for script execution
$culture = "EN-US"

# Backup current culture
$OldCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
$OldUICulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture


# Set new Culture for script execution
[System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = $culture

####################################################

$itunesApps = Get-itunesApplication -SearchString "Microsoft Corporation" -Limit 50

#region Office Example
$Applications = 'Microsoft Outlook','Microsoft Excel','OneDrive'
#endregion

# If application list is specified
if($Applications) {

    # Looping through applications list
    foreach($Application in $Applications){

    $itunesApp = $itunesApps.results | ? { ($_.trackName).contains("$Application") }

        # if single application count is greater than 1 loop through names
        if($itunesApp.count -gt 1){

        $itunesApp.count
        write-host "More than 1 application was found in the itunes store" -f Cyan

            foreach($iapp in $itunesApp){

            $Create_App = Add-iOSApplication -itunesApp $iApp

            $ApplicationId = $Create_App.id

            $Assign_App = Add-ApplicationAssignment -ApplicationId $ApplicationId -TargetGroupId $TargetGroupId -InstallIntent "available"
            Write-Host "Assigned '$AADGroup' to $($Create_App.displayName)/$($create_App.id) with" $Assign_App.InstallIntent "install Intent"

            Write-Host

            }

        }

        # Single application found, adding application
        elseif($itunesApp){

        $Create_App = Add-iOSApplication -itunesApp $itunesApp

        $ApplicationId = $Create_App.id

        $Assign_App = Add-ApplicationAssignment -ApplicationId $ApplicationId -TargetGroupId $TargetGroupId -InstallIntent "available"
        Write-Host "Assigned '$AADGroup' to $($Create_App.displayName)/$($create_App.id) with" $Assign_App.InstallIntent "install Intent"

        Write-Host

        }

        # if application isn't found in itunes returning doesn't exist
        else {

        write-host
        write-host "Application '$Application' doesn't exist" -f Red
        write-host

        }

    }

}

# No Applications have been specified
else {

    # if there are results returned from itunes query
    if($itunesApps.results){

    write-host
    write-host "Number of iOS applications to add:" $itunesApps.results.count -f Yellow
    Write-Host

        # Looping through applications returned from itunes
        foreach($itunesApp in $itunesApps.results){

        $Create_App = Add-iOSApplication -itunesApp $itunesApp

        $ApplicationId = $Create_App.id

        $Assign_App = Add-ApplicationAssignment -ApplicationId $ApplicationId -TargetGroupId $TargetGroupId -InstallIntent "available"
        Write-Host "Assigned '$AADGroup' to $($Create_App.displayName)/$($create_App.id) with" $Assign_App.InstallIntent "install Intent"

        Write-Host

        }

    }

    # No applications returned from itunes
    else {

    write-host
    write-host "No applications found..." -f Red
    write-host

    }

}
#Restore culture from backup
[System.Threading.Thread]::CurrentThread.CurrentCulture = $OldCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = $OldUICulture

