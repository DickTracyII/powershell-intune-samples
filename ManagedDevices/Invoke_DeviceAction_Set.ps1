
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
            "DeviceManagementConfiguration.ReadWrite.All",
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

function Get-AADUser {

<#
.SYNOPSIS
This function is used to get AAD Users from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any users registered with AAD
.EXAMPLE
Get-AADUser
Returns all users registered with Azure AD
.EXAMPLE
Get-AADUser -userPrincipleName user@domain.com
Returns specific user by UserPrincipalName registered with Azure AD
.NOTES
NAME: Get-AADUser
#>

[cmdletbinding()]

param
(
    $userPrincipalName,
    $Property
)

# Defining Variables
$graphApiVersion = "v1.0"
$User_resource = "users"

    try {

        if("" -eq $userPrincipalName -or $null -eq $userPrincipalName){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($User_resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value

        }

        else {

            if("" -eq $Property -or $null -eq $Property){

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($User_resource)/$userPrincipalName"
            Write-Verbose $uri
            Invoke-IntuneRestMethod -Uri $uri -Method GET

            }

            else {

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($User_resource)/$userPrincipalName/$Property"
            Write-Verbose $uri
            (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value

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

function Get-AADUserDevices {

<#
.SYNOPSIS
This function is used to get an AAD User Devices from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets a users devices registered with Intune MDM
.EXAMPLE
Get-AADUserDevices -UserID $UserID
Returns all user devices registered in Intune MDM
.NOTES
NAME: Get-AADUserDevices
#>

[cmdletbinding()]

param
(
    [Parameter(Mandatory=$true,HelpMessage="UserID (guid) for the user you want to take action on must be specified:")]
    $UserID
)

# Defining Variables
$graphApiVersion = "beta"
$Resource = "users/$UserID/managedDevices"

    try {

    $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
    Write-Verbose $uri
    (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value

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

function Invoke-DeviceAction {

<#
.SYNOPSIS
This function is used to set a generic intune resources from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and sets a generic Intune Resource
.EXAMPLE
Invoke-DeviceAction -DeviceID $DeviceID -remoteLock
Resets a managed device passcode
.NOTES
NAME: Invoke-DeviceAction
#>

[cmdletbinding()]

param
(
    [switch]$RemoteLock,
    [switch]$ResetPasscode,
    [switch]$Wipe,
    [switch]$Retire,
    [switch]$Delete,
    [switch]$Sync,
    [switch]$Rename,
    [Parameter(Mandatory=$true,HelpMessage="DeviceId (guid) for the Device you want to take action on must be specified:")]
    $DeviceID
)

$graphApiVersion = "Beta"

    try {

        $Count_Params = 0

        if($RemoteLock.IsPresent){ $Count_Params++ }
        if($ResetPasscode.IsPresent){ $Count_Params++ }
        if($Wipe.IsPresent){ $Count_Params++ }
        if($Retire.IsPresent){ $Count_Params++ }
        if($Delete.IsPresent){ $Count_Params++ }
        if($Sync.IsPresent){ $Count_Params++ }
        if($Rename.IsPresent){ $Count_Params++ }

        if($Count_Params -eq 0){

        write-host "No parameter set, specify -RemoteLock -ResetPasscode -Wipe -Delete -Sync or -rename against the function" -f Red

        }

        elseif($Count_Params -gt 1){

        write-host "Multiple parameters set, specify a single parameter -RemoteLock -ResetPasscode -Wipe -Delete or -Sync against the function" -f Red

        }

        elseif($RemoteLock){

        $Resource = "deviceManagement/managedDevices/$DeviceID/remoteLock"
        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        write-verbose $uri
        Write-Verbose "Sending remoteLock command to $DeviceID"
        Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post

        }

        elseif($ResetPasscode){

            write-host
            write-host "Are you sure you want to reset the Passcode this device? Y or N?"
            $Confirm = read-host

            if($Confirm -eq "y" -or $Confirm -eq "Y"){

            $Resource = "deviceManagement/managedDevices/$DeviceID/resetPasscode"
            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            write-verbose $uri
            Write-Verbose "Sending remotePasscode command to $DeviceID"
            Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post

            }

            else {

            Write-Host "Reset of the Passcode for the device $DeviceID was cancelled..."

            }

        }

        elseif($Wipe){

        write-host
        write-host "Are you sure you want to wipe this device? Y or N?"
        $Confirm = read-host

            if($Confirm -eq "y" -or $Confirm -eq "Y"){

            $Resource = "deviceManagement/managedDevices/$DeviceID/wipe"
            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            write-verbose $uri
            Write-Verbose "Sending wipe command to $DeviceID"
            Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post

            }

            else {

            Write-Host "Wipe of the device $DeviceID was cancelled..."

            }

        }

        elseif($Retire){

        write-host
        write-host "Are you sure you want to retire this device? Y or N?"
        $Confirm = read-host

            if($Confirm -eq "y" -or $Confirm -eq "Y"){

            $Resource = "deviceManagement/managedDevices/$DeviceID/retire"
            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            write-verbose $uri
            Write-Verbose "Sending retire command to $DeviceID"
            Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post

            }

            else {

            Write-Host "Retire of the device $DeviceID was cancelled..."

            }

        }

        elseif($Delete){

        write-host
        Write-Warning "A deletion of a device will only work if the device has already had a retire or wipe request sent to the device..."
        Write-Host
        write-host "Are you sure you want to delete this device? Y or N?"
        $Confirm = read-host

            if($Confirm -eq "y" -or $Confirm -eq "Y"){

            $Resource = "deviceManagement/managedDevices('$DeviceID')"
            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            write-verbose $uri
            Write-Verbose "Sending delete command to $DeviceID"
            Invoke-RestMethod -Uri $uri -Headers $authToken -Method Delete

            }

            else {

            Write-Host "Deletion of the device $DeviceID was cancelled..."

            }

        }

        elseif($Sync){

        write-host
        write-host "Are you sure you want to sync this device? Y or N?"
        $Confirm = read-host

            if($Confirm -eq "y" -or $Confirm -eq "Y"){

            $Resource = "deviceManagement/managedDevices('$DeviceID')/syncDevice"
            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            write-verbose $uri
            Write-Verbose "Sending sync command to $DeviceID"
            Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post

            }

            else {

            Write-Host "Sync of the device $DeviceID was cancelled..."

            }

        }

        elseif($Rename){

        write-host "Please type the new device name:" -ForegroundColor Yellow
        $NewDeviceName = Read-Host

$JSON = @"

{
    deviceName:"$($NewDeviceName)"
}

"@

        write-host
        write-host "Note: The RenameDevice remote action is only supported on supervised iOS and Windows 10 Azure AD joined devices"
        write-host "Are you sure you want to rename this device to" $($NewDeviceName) "(Y or N?)"
        $Confirm = read-host

            if($Confirm -eq "y" -or $Confirm -eq "Y"){

            $Resource = "deviceManagement/managedDevices('$DeviceID')/setDeviceName"
            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            write-verbose $uri
            Write-Verbose "Sending rename command to $DeviceID"
            Invoke-IntuneRestMethod -Uri $uri -Method POST -Body $JSON

            }

            else {

            Write-Host "Rename of the device $DeviceID was cancelled..."

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

write-host
write-host "User Principal Name:" -f Yellow
$UPN = Read-Host

write-host

$User = Get-AADUser -userPrincipalName $UPN

$id = $User.Id
write-host "User ID:"$id

####################################################
# Get Users Devices
####################################################

Write-Host
Write-Host "Checking if the user" $User.displayName "has any devices assigned..." -ForegroundColor DarkCyan

$Devices = Get-AADUserDevices -UserID $id

####################################################
# Invoke-DeviceAction
####################################################

if($Devices){

$DeviceCount = @($Devices).count

Write-Host
Write-Host "User has $DeviceCount devices added to Intune..."
Write-Host

    if($Devices.id.count -gt 1){

    $Managed_Devices = $Devices.deviceName | sort -Unique

    $menu = @{}

    for ($i=1;$i -le $Managed_Devices.count; $i++)
    { Write-Host "$i. $($Managed_Devices[$i-1])"
    $menu.Add($i,($Managed_Devices[$i-1]))}

    Write-Host
    [int]$ans = Read-Host 'Enter Device id (Numerical value)'
    $selection = $menu.Item($ans)

        if($selection){

        $SelectedDevice = $Devices | ? { $_.deviceName -eq "$Selection" }

        $SelectedDeviceId = $SelectedDevice | select -ExpandProperty id

        write-host "User" $User.userPrincipalName "has device" $SelectedDevice.deviceName
        #Invoke-DeviceAction -DeviceID $SelectedDeviceId -RemoteLock -Verbose
        #Invoke-DeviceAction -DeviceID $SelectedDeviceId -Retire -Verbose
        #Invoke-DeviceAction -DeviceID $SelectedDeviceId -Wipe -Verbose
        #Invoke-DeviceAction -DeviceID $SelectedDeviceId -Delete -Verbose
        #Invoke-DeviceAction -DeviceID $SelectedDeviceId -Sync -Verbose
        #Invoke-DeviceAction -DeviceID $SelectedDeviceId -Rename -Verbose

        }

    }

    elseif($Devices.id.count -eq 1){

        write-host "User" $User.userPrincipalName "has one device" $Devices.deviceName
        #Invoke-DeviceAction -DeviceID $Devices.id -RemoteLock -Verbose
        #Invoke-DeviceAction -DeviceID $Devices.id -Retire -Verbose
        #Invoke-DeviceAction -DeviceID $Devices.id -Wipe -Verbose
        #Invoke-DeviceAction -DeviceID $Devices.id -Delete -Verbose
        #Invoke-DeviceAction -DeviceID $Devices.id -Sync -Verbose
        #Invoke-DeviceAction -DeviceID $Devices.id -Rename -Verbose

    }

}

else {

Write-Host
write-host "User $UPN doesn't have any owned Devices..." -f Yellow

}

write-host




