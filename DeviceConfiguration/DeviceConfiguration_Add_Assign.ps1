
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

function Add-DeviceConfigurationPolicy {

<#
.SYNOPSIS
This function is used to add an device configuration policy using the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and adds a device configuration policy
.EXAMPLE
Add-DeviceConfigurationPolicy -JSON $JSON
Adds a device configuration policy in Intune
.NOTES
NAME: Add-DeviceConfigurationPolicy
#>

[cmdletbinding()]

param
(
    $JSON
)

$graphApiVersion = "Beta"
$DCP_resource = "deviceManagement/deviceConfigurations"
Write-Verbose "Resource: $DCP_resource"

    try {

        if("" -eq $JSON -or $null -eq $JSON){

        write-host "No JSON specified, please specify valid JSON for the Android Policy..." -f Red

        }

        else {

        Test-JSON -JSON $JSON

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($DCP_resource)"
        Invoke-IntuneRestMethod -Uri $uri -Method POST -Body $JSON

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

function Add-DeviceConfigurationPolicyAssignment {

    <#
    .SYNOPSIS
    This function is used to add a device configuration policy assignment using the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and adds a device configuration policy assignment
    .EXAMPLE
    Add-DeviceConfigurationPolicyAssignment -ConfigurationPolicyId $ConfigurationPolicyId -TargetGroupId $TargetGroupId -AssignmentType Included
    Adds a device configuration policy assignment in Intune
    .NOTES
    NAME: Add-DeviceConfigurationPolicyAssignment
    #>

    [cmdletbinding()]

    param
    (
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $ConfigurationPolicyId,

        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $TargetGroupId,

        [parameter(Mandatory=$true)]
        [ValidateSet("Included","Excluded")]
        [ValidateNotNullOrEmpty()]
        [string]$AssignmentType
    )

    $graphApiVersion = "Beta"
    $Resource = "deviceManagement/deviceConfigurations/$ConfigurationPolicyId/assign"

        try {

            if(!$ConfigurationPolicyId){

                write-host "No Configuration Policy Id specified, specify a valid Configuration Policy Id" -f Red
                break

            }

            if(!$TargetGroupId){

                write-host "No Target Group Id specified, specify a valid Target Group Id" -f Red
                break

            }

            # Checking if there are Assignments already configured in the Policy
            $DCPA = Get-DeviceConfigurationPolicyAssignment -id $ConfigurationPolicyId

            $TargetGroups = @()

            if(@($DCPA).count -ge 1){

                if($DCPA.targetGroupId -contains $TargetGroupId){

                Write-Host "Group with Id '$TargetGroupId' already assigned to Policy..." -ForegroundColor Red
                Write-Host
                break

                }

                # Looping through previously configured assignements

                $DCPA | foreach {

                $TargetGroup = New-Object -TypeName psobject

                    if($_.excludeGroup -eq $true){

                        $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.exclusionGroupAssignmentTarget'

                    }

                    else {

                        $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.groupAssignmentTarget'

                    }

                $TargetGroup | Add-Member -MemberType NoteProperty -Name 'groupId' -Value $_.targetGroupId

                $Target = New-Object -TypeName psobject
                $Target | Add-Member -MemberType NoteProperty -Name 'target' -Value $TargetGroup

                $TargetGroups += $Target

                }

                # Adding new group to psobject
                $TargetGroup = New-Object -TypeName psobject

                    if($AssignmentType -eq "Excluded"){

                        $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.exclusionGroupAssignmentTarget'

                    }

                    elseif($AssignmentType -eq "Included") {

                        $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.groupAssignmentTarget'

                    }

                $TargetGroup | Add-Member -MemberType NoteProperty -Name 'groupId' -Value "$TargetGroupId"

                $Target = New-Object -TypeName psobject
                $Target | Add-Member -MemberType NoteProperty -Name 'target' -Value $TargetGroup

                $TargetGroups += $Target

            }

            else {

                # No assignments configured creating new JSON object of group assigned

                $TargetGroup = New-Object -TypeName psobject

                    if($AssignmentType -eq "Excluded"){

                        $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.exclusionGroupAssignmentTarget'

                    }

                    elseif($AssignmentType -eq "Included") {

                        $TargetGroup | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.groupAssignmentTarget'

                    }

                $TargetGroup | Add-Member -MemberType NoteProperty -Name 'groupId' -Value "$TargetGroupId"

                $Target = New-Object -TypeName psobject
                $Target | Add-Member -MemberType NoteProperty -Name 'target' -Value $TargetGroup

                $TargetGroups = $Target

            }

        # Creating JSON object to pass to Graph
        $Output = New-Object -TypeName psobject

        $Output | Add-Member -MemberType NoteProperty -Name 'assignments' -Value @($TargetGroups)

        $JSON = $Output | ConvertTo-Json -Depth 3

        # POST to Graph Service
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

function Get-DeviceConfigurationPolicyAssignment {

    <#
    .SYNOPSIS
    This function is used to get device configuration policy assignment from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets a device configuration policy assignment
    .EXAMPLE
    Get-DeviceConfigurationPolicyAssignment $id guid
    Returns any device configuration policy assignment configured in Intune
    .NOTES
    NAME: Get-DeviceConfigurationPolicyAssignment
    #>

    [cmdletbinding()]

    param
    (
        [Parameter(Mandatory=$true,HelpMessage="Enter id (guid) for the Device Configuration Policy you want to check assignment")]
        $id
    )

    $graphApiVersion = "Beta"
    $DCP_resource = "deviceManagement/deviceConfigurations"

        try {

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($DCP_resource)/$id/groupAssignments"
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

function Test-JSON {

<#
.SYNOPSIS
This function is used to test if the JSON passed to a REST Post request is valid
.DESCRIPTION
The function tests if the JSON passed to the REST Post is valid
.EXAMPLE
Test-JSON -JSON $JSON
Test if the JSON is valid before calling the Graph REST interface
.NOTES
NAME: Test-AuthHeader
#>

param (

$JSON

)

    try {

    $TestJSON = ConvertFrom-Json $JSON -ErrorAction Stop
    $validJson = $true

    }

    catch {

    $validJson = $false
    $_.Exception

    }

    if (!$validJson){

    Write-Host "Provided JSON isn't in valid JSON format" -f Red
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

$iOS = @"

{
    "@odata.type": "#microsoft.graph.iosGeneralDeviceConfiguration",
    "description": "",
    "displayName": "iOS Device Restriction Policy",
    "accountBlockModification": false,
    "activationLockAllowWhenSupervised": false,
    "airDropBlocked": false,
    "airDropForceUnmanagedDropTarget": false,
    "airPlayForcePairingPasswordForOutgoingRequests": false,
    "appleWatchBlockPairing": false,
    "appleWatchForceWristDetection": false,
    "appleNewsBlocked": false,
    "appsSingleAppModeBundleIds": [],
    "appsVisibilityList": [],
    "appsVisibilityListType": "none",
    "appStoreBlockAutomaticDownloads": false,
    "appStoreBlocked": false,
    "appStoreBlockInAppPurchases": false,
    "appStoreBlockUIAppInstallation": false,
    "appStoreRequirePassword": false,
    "bluetoothBlockModification": false,
    "cameraBlocked": false,
    "cellularBlockDataRoaming": false,
    "cellularBlockGlobalBackgroundFetchWhileRoaming": false,
    "cellularBlockPerAppDataModification": false,
    "cellularBlockVoiceRoaming": false,
    "certificatesBlockUntrustedTlsCertificates": false,
    "classroomAppBlockRemoteScreenObservation": false,
    "compliantAppsList": [],
    "compliantAppListType": "none",
    "configurationProfileBlockChanges": false,
    "definitionLookupBlocked": false,
    "deviceBlockEnableRestrictions": false,
    "deviceBlockEraseContentAndSettings": false,
    "deviceBlockNameModification": false,
    "diagnosticDataBlockSubmission": false,
    "diagnosticDataBlockSubmissionModification": false,
    "documentsBlockManagedDocumentsInUnmanagedApps": false,
    "documentsBlockUnmanagedDocumentsInManagedApps": false,
    "emailInDomainSuffixes": [],
    "enterpriseAppBlockTrust": false,
    "enterpriseAppBlockTrustModification": false,
    "faceTimeBlocked": false,
    "findMyFriendsBlocked": false,
    "gamingBlockGameCenterFriends": true,
    "gamingBlockMultiplayer": false,
    "gameCenterBlocked": false,
    "hostPairingBlocked": false,
    "iBooksStoreBlocked": false,
    "iBooksStoreBlockErotica": false,
    "iCloudBlockActivityContinuation": false,
    "iCloudBlockBackup": true,
    "iCloudBlockDocumentSync": true,
    "iCloudBlockManagedAppsSync": false,
    "iCloudBlockPhotoLibrary": false,
    "iCloudBlockPhotoStreamSync": true,
    "iCloudBlockSharedPhotoStream": false,
    "iCloudRequireEncryptedBackup": false,
    "iTunesBlockExplicitContent": false,
    "iTunesBlockMusicService": false,
    "iTunesBlockRadio": false,
    "keyboardBlockAutoCorrect": false,
    "keyboardBlockPredictive": false,
    "keyboardBlockShortcuts": false,
    "keyboardBlockSpellCheck": false,
    "kioskModeAllowAssistiveSpeak": false,
    "kioskModeAllowAssistiveTouchSettings": false,
    "kioskModeAllowAutoLock": false,
    "kioskModeAllowColorInversionSettings": false,
    "kioskModeAllowRingerSwitch": false,
    "kioskModeAllowScreenRotation": false,
    "kioskModeAllowSleepButton": false,
    "kioskModeAllowTouchscreen": false,
    "kioskModeAllowVoiceOverSettings": false,
    "kioskModeAllowVolumeButtons": false,
    "kioskModeAllowZoomSettings": false,
    "kioskModeAppStoreUrl": null,
    "kioskModeRequireAssistiveTouch": false,
    "kioskModeRequireColorInversion": false,
    "kioskModeRequireMonoAudio": false,
    "kioskModeRequireVoiceOver": false,
    "kioskModeRequireZoom": false,
    "kioskModeManagedAppId": null,
    "lockScreenBlockControlCenter": false,
    "lockScreenBlockNotificationView": false,
    "lockScreenBlockPassbook": false,
    "lockScreenBlockTodayView": false,
    "mediaContentRatingAustralia": null,
    "mediaContentRatingCanada": null,
    "mediaContentRatingFrance": null,
    "mediaContentRatingGermany": null,
    "mediaContentRatingIreland": null,
    "mediaContentRatingJapan": null,
    "mediaContentRatingNewZealand": null,
    "mediaContentRatingUnitedKingdom": null,
    "mediaContentRatingUnitedStates": null,
    "mediaContentRatingApps": "allAllowed",
    "messagesBlocked": false,
    "notificationsBlockSettingsModification": false,
    "passcodeBlockFingerprintUnlock": false,
    "passcodeBlockModification": false,
    "passcodeBlockSimple": true,
    "passcodeExpirationDays": null,
    "passcodeMinimumLength": 4,
    "passcodeMinutesOfInactivityBeforeLock": null,
    "passcodeMinutesOfInactivityBeforeScreenTimeout": null,
    "passcodeMinimumCharacterSetCount": null,
    "passcodePreviousPasscodeBlockCount": null,
    "passcodeSignInFailureCountBeforeWipe": null,
    "passcodeRequiredType": "deviceDefault",
    "passcodeRequired": true,
    "podcastsBlocked": false,
    "safariBlockAutofill": false,
    "safariBlockJavaScript": false,
    "safariBlockPopups": false,
    "safariBlocked": false,
    "safariCookieSettings": "browserDefault",
    "safariManagedDomains": [],
    "safariPasswordAutoFillDomains": [],
    "safariRequireFraudWarning": false,
    "screenCaptureBlocked": false,
    "siriBlocked": false,
    "siriBlockedWhenLocked": false,
    "siriBlockUserGeneratedContent": false,
    "siriRequireProfanityFilter": false,
    "spotlightBlockInternetResults": false,
    "voiceDialingBlocked": false,
    "wallpaperBlockModification": false
}

"@

####################################################

$Android = @"

{
    "@odata.type": "#microsoft.graph.androidGeneralDeviceConfiguration",
    "description": "",
    "displayName": "Android Device Restriction Policy",
    "appsBlockClipboardSharing": false,
    "appsBlockCopyPaste": false,
    "appsBlockYouTube": false,
    "bluetoothBlocked": false,
    "cameraBlocked": false,
    "cellularBlockDataRoaming": true,
    "cellularBlockMessaging": false,
    "cellularBlockVoiceRoaming": false,
    "cellularBlockWiFiTethering": false,
    "compliantAppsList": [],
    "compliantAppListType": "none",
    "diagnosticDataBlockSubmission": false,
    "locationServicesBlocked": false,
    "googleAccountBlockAutoSync": false,
    "googlePlayStoreBlocked": false,
    "kioskModeBlockSleepButton": false,
    "kioskModeBlockVolumeButtons": false,
    "kioskModeManagedAppId": null,
    "nfcBlocked": false,
    "passwordBlockFingerprintUnlock": true,
    "passwordBlockTrustAgents": false,
    "passwordExpirationDays": null,
    "passwordMinimumLength": 4,
    "passwordMinutesOfInactivityBeforeScreenTimeout": null,
    "passwordPreviousPasswordBlockCount": null,
    "passwordSignInFailureCountBeforeFactoryReset": null,
    "passwordRequiredType": "deviceDefault",
    "passwordRequired": true,
    "powerOffBlocked": false,
    "factoryResetBlocked": false,
    "screenCaptureBlocked": false,
    "deviceSharingBlocked": false,
    "storageBlockGoogleBackup": true,
    "storageBlockRemovableStorage": false,
    "storageRequireDeviceEncryption": true,
    "storageRequireRemovableStorageEncryption": true,
    "voiceAssistantBlocked": false,
    "voiceDialingBlocked": false,
    "webBrowserAllowPopups": false,
    "webBrowserBlockAutofill": false,
    "webBrowserBlockJavaScript": false,
    "webBrowserBlocked": false,
    "webBrowserCookieSettings": "browserDefault",
    "wiFiBlocked": false
}

"@

####################################################

# Setting application AAD Group to assign Policy

$AADGroup = Read-Host -Prompt "Enter the Azure AD Group name where policies will be assigned"

$TargetGroupId = (get-AADGroup -GroupName "$AADGroup").id

    if($null -eq $TargetGroupId -or "" -eq $TargetGroupId){

    Write-Host "AAD Group - '$AADGroup' doesn't exist, please specify a valid AAD Group..." -ForegroundColor Red
    Write-Host
    exit

    }

####################################################

Write-Host "Adding Android Device Restriction Policy from JSON..." -ForegroundColor Yellow

$CreateResult_Android = Add-DeviceConfigurationPolicy -JSON $Android

Write-Host "Device Restriction Policy created as" $CreateResult_Android.id
write-host
write-host "Assigning Device Restriction Policy to AAD Group '$AADGroup'" -f Cyan

$Assign_Android = Add-DeviceConfigurationPolicyAssignment -ConfigurationPolicyId $CreateResult_Android.id -TargetGroupId $TargetGroupId -AssignmentType Included

Write-Host "Assigned '$AADGroup' to $($CreateResult_Android.displayName)/$($CreateResult_Android.id)"
Write-Host

####################################################

Write-Host "Adding iOS Device Restriction Policy from JSON..." -ForegroundColor Yellow
Write-Host

$CreateResult_iOS = Add-DeviceConfigurationPolicy -JSON $iOS

Write-Host "Device Restriction Policy created as" $CreateResult_iOS.id
write-host
write-host "Assigning Device Restriction Policy to AAD Group '$AADGroup'" -f Cyan

$Assign_iOS = Add-DeviceConfigurationPolicyAssignment -ConfigurationPolicyId $CreateResult_iOS.id -TargetGroupId $TargetGroupId -AssignmentType Included

Write-Host "Assigned '$AADGroup' to $($CreateResult_iOS.displayName)/$($CreateResult_iOS.id)"
Write-Host

