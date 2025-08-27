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
            "User.Read.All"
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

function Get-ManagedAppPolicy {

<#
.SYNOPSIS
This function is used to get managed app policies (AppConfig) from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any managed app policies
.EXAMPLE
Get-ManagedAppPolicy
Returns any managed app policies configured in Intune
.NOTES
NAME: Get-ManagedAppPolicy
#>

[cmdletbinding()]

param
(
)

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/managedAppPolicies"

    try {


        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'@odata.type').contains("ManagedAppProtection") -or ($_.'@odata.type').contains("InformationProtectionPolicy") }

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

function Get-ManagedAppProtection {

<#
.SYNOPSIS
This function is used to get managed app protection configuration from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any managed app protection policy
.EXAMPLE
Get-ManagedAppProtection -id $id -OS "Android"
Returns a managed app protection policy for Android configured in Intune
Get-ManagedAppProtection -id $id -OS "iOS"
Returns a managed app protection policy for iOS configured in Intune
Get-ManagedAppProtection -id $id -OS "WIP_WE"
Returns a managed app protection policy for Windows 10 without enrollment configured in Intune
.NOTES
NAME: Get-ManagedAppProtection
#>

[cmdletbinding()]

param
(
    $id,
    $OS
)

$graphApiVersion = "Beta"

    try {

        if("" -eq $id -or $null -eq $id){

        write-host "No Managed App Policy id specified, please provide a policy id..." -f Red
        break

        }

        else {

            if("" -eq $OS -or $null -eq $OS){

            write-host "No OS parameter specified, please provide an OS. Supported values are Android,iOS, and Windows..." -f Red
            Write-Host
            break

            }

            elseif($OS -eq "Android"){

            $Resource = "deviceAppManagement/androidManagedAppProtections('$id')/?`$expand=deploymentSummary,apps,assignments"

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            Invoke-IntuneRestMethod -Uri $uri -Method GET

            }

            elseif($OS -eq "iOS"){

            $Resource = "deviceAppManagement/iosManagedAppProtections('$id')/?`$expand=deploymentSummary,apps,assignments"

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            Invoke-IntuneRestMethod -Uri $uri -Method GET

            }

            elseif($OS -eq "Windows"){

            $Resource = "deviceAppManagement/windowsInformationProtectionPolicies('$id')?`$expand=protectedAppLockerFiles,exemptAppLockerFiles,assignments"

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            Invoke-IntuneRestMethod -Uri $uri -Method GET

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

function Get-ApplicationAssignment {

<#
.SYNOPSIS
This function is used to get an application assignment from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets an application assignment
.EXAMPLE
Get-ApplicationAssignment
Returns an Application Assignment configured in Intune
.NOTES
NAME: Get-ApplicationAssignment
#>

[cmdletbinding()]

param
(
    $ApplicationId
)

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/mobileApps/$ApplicationId/assignments"

    try {

        if(!$ApplicationId){

        write-host "No Application Id specified, specify a valid Application Id" -f Red
        break

        }

        else {

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value

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

function Get-MobileAppConfigurations {

<#
.SYNOPSIS
This function is used to get all Mobile App Configuration Policies (managed device) using the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets all Mobile App Configuration Policies from the itunes store
.EXAMPLE
Get-MobileAppConfigurations
Gets all Mobile App Configuration Policies configured in the Intune Service
.NOTES
NAME: Get-MobileAppConfigurations
#>

[cmdletbinding()]

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/mobileAppConfigurations?`$expand=assignments"

    try {

    $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"

    Invoke-IntuneRestMethod -Uri $uri -Method GET


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

function Get-TargetedManagedAppConfigurations {

<#
.SYNOPSIS
This function is used to get all Targeted Managed App Configuration Policies using the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets all Targeted Managed App Configuration Policies from the itunes store
.EXAMPLE
Get-TargetedManagedAppConfigurations
Gets all Targeted Managed App Configuration Policies configured in the Intune Service
.NOTES
NAME: Get-TargetedManagedAppConfigurations
#>

[cmdletbinding()]

param
(
    [Parameter(Mandatory=$false)]
    $PolicyId
)

$graphApiVersion = "Beta"

    try {

        if($PolicyId){

            $Resource = "deviceAppManagement/targetedManagedAppConfigurations('$PolicyId')?`$expand=apps,assignments"
            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            (Invoke-IntuneRestMethod -Uri $uri -Method GET)

        }

        else {

            $Resource = "deviceAppManagement/targetedManagedAppConfigurations"
            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            Invoke-IntuneRestMethod -Uri $uri -Method GET

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

function Get-IntuneApplication {

<#
.SYNOPSIS
This function is used to get applications from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any applications added
.EXAMPLE
Get-IntuneApplication
Returns any applications configured in Intune
.NOTES
NAME: Get-IntuneApplication
#>

[cmdletbinding()]

param
(
    $id,
    $Name
)

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/mobileApps"

    try {

        if($id){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)/$id"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET)

        }


        elseif($Name){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'displayName').contains("$Name") -and (!($_.'@odata.type').Contains("managed")) }

        }

        else {

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { (!($_.'@odata.type').Contains("managed")) }

        }

    }

    catch {

    $ex = $_.Exception
    Write-Host "Request to $Uri failed with HTTP Status $([int]$ex.Response.StatusCode) $($ex.Response.StatusDescription)" -f Red
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

function Get-IntuneMAMApplication {

<#
.SYNOPSIS
This function is used to get MAM applications from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any MAM applications
.EXAMPLE
Get-IntuneMAMApplication
Returns any MAM applications configured in Intune
.NOTES
NAME: Get-IntuneMAMApplication
#>

[cmdletbinding()]

param
(
$packageid,
$bundleid
)

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/mobileApps"

    try {

        if($packageid){

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | ? { ($_.'@odata.type').Contains("managed") -and ($_.'appAvailability' -eq "Global") -and ($_.'packageid' -eq "$packageid") }

        }

        elseif($bundleid){

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | ? { ($_.'@odata.type').Contains("managed") -and ($_.'appAvailability' -eq "Global") -and ($_.'bundleid' -eq "$bundleid") }

        }

        else {

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | ? { ($_.'@odata.type').Contains("managed") -and ($_.'appAvailability' -eq "Global") }

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

write-host "This script outputs the Intune app protection policies and application configuration policies assigned to a user."
Write-Host

Write-Warning "This script doesn't support configurations applied to nested group members"

Write-Host
write-host "Enter the UPN:" -f Yellow
$UPN = Read-Host

if($null -eq $UPN -or "" -eq $UPN){

    write-host "User Principal Name is Null..." -ForegroundColor Red
    Write-Host "Script can't continue..." -ForegroundColor Red
    Write-Host
    break

}

$User = Get-AADUser -userPrincipalName $UPN

if(!$User){ break }

$UserID = $User.id

write-host
write-host "-------------------------------------------------------------------"
Write-Host
write-host "Display Name:"$User.displayName
write-host "User Principal Name:"$User.userPrincipalName
Write-Host
write-host "-------------------------------------------------------------------"
write-host

####################################################

$OSChoices = "Android","iOS"

#region menu

$OSChoicesCount = "2"

    $menu = @{}

    for ($i=1;$i -le $OSChoices.count; $i++)
    { Write-Host "$i. $($OSChoices[$i-1])"
    $menu.Add($i,($OSChoices[$i-1]))}

    Write-Host
    $ans = Read-Host 'Choose an OS (numerical value)'

    if("" -eq $ans -or $null -eq $ans){

    Write-Host "OS choice can't be null, please specify a valid OS..." -ForegroundColor Red
    Write-Host
    break

    }

    elseif(($ans -match "^[\d\.]+$") -eq $true){

    $selection = $menu.Item([int]$ans)

        if($selection){

            $OS = $OSChoices | ? { $_ -eq "$Selection" }

        }

        else {

            Write-Host "OS choice selection invalid, please specify a valid OS..." -ForegroundColor Red
            Write-Host
            break

        }

    }

    else {

        Write-Host "OS choice not an integer, please specify a valid OS..." -ForegroundColor Red
        Write-Host
        break

    }

    Write-Host

#endregion

$MemberOf = Get-AADUser -userPrincipalName $UPN -Property MemberOf

$AADGroups = $MemberOf | ? { $_.'@odata.type' -eq "#microsoft.graph.group" }

####################################################

#region App Protection Policies

write-host "-------------------------------------------------------------------"
Write-Host
Write-Host "App Protection Policies: $OS" -ForegroundColor Cyan
Write-Host
write-host "-------------------------------------------------------------------"
Write-Host

$ManagedAppPolicies = Get-ManagedAppPolicy | ? {$_.'@odata.type' -like "*$os*"}

if($ManagedAppPolicies){

$AssignmentCount = 0

    foreach($ManagedAppPolicy in $ManagedAppPolicies){

        # If Android Managed App Policy

        if($ManagedAppPolicy.'@odata.type' -eq "#microsoft.graph.androidManagedAppProtection"){

            $AndroidManagedAppProtection = Get-ManagedAppProtection -id $ManagedAppPolicy.id -OS "Android"

            $MAMApps = $AndroidManagedAppProtection.apps

            $AndroidAssignments = ($AndroidManagedAppProtection | select assignments).assignments

            if($AndroidAssignments){

                foreach($Group in $AndroidAssignments.target){

                    if($AADGroups.id -contains $Group.groupId){

                    $AssignmentCount++

                    $GroupID = $Group.GroupId
                    $GroupTargetType = $Group.'@odata.type'.split(".")[-1]

                    $targetedAppManagementLevels = $AndroidManagedAppProtection.targetedAppManagementLevels

                        switch ($targetedAppManagementLevels){

                            "unspecified" {$ManagementType = "All app types";break}
                            "mdm" {$ManagementType = "Apps on managed devices";break}
                            "unmanaged" {$ManagementType = "Apps on unmanaged devices";break}

                            }

                    write-host "Policy name: " -NoNewline
                    write-host $AndroidManagedAppProtection.displayname -ForegroundColor Green
                    write-host "Group assigned: " -NoNewline
                    write-host (get-aadgroup -id $GroupID).displayname

                    if($GroupTargetType -eq "exclusionGroupAssignmentTarget"){

                        Write-Host "Group Target: " -NoNewline
                        Write-Host "Excluded" -ForegroundColor Red

                    }

                    elseif($GroupTargetType -eq "GroupAssignmentTarget"){

                        Write-Host "Group Target: " -NoNewline
                        Write-Host "Included" -ForegroundColor Green

                    }

                    Write-Host
                    Write-Host "Targeted Apps:" -ForegroundColor Yellow

                    foreach($MAMApp in $MAMApps){

                        $AppName = (Get-IntuneMAMApplication -packageId $MAMApp.mobileAppIdentifier.packageId).displayName

                        if($AppName){ $AppName }
                        else { $MAMApp.mobileAppIdentifier.packageId }

                    }

                    Write-Host
                    Write-Host "Configuration Settings:" -ForegroundColor Yellow
                    Write-Host "Targeted management type: $ManagementType"
                    Write-Host "Jailbroken/rooted devices blocked: $($AndroidManagedAppProtection.deviceComplianceRequired)"
                    Write-Host "Min OS version: $($AndroidManagedAppProtection.minimumRequiredOsVersion)"
                    Write-Host "Min patch version: $($AndroidManagedAppProtection.minimumRequiredPatchVersion)"
                    Write-Host "Allowed device manufacturer(s): $($AndroidManagedAppProtection.allowedAndroidDeviceManufacturers)"
                    write-host "Require managed browser: $($AndroidManagedAppProtection.managedBrowserToOpenLinksRequired)"
                    Write-Host "Contact sync blocked: $($AndroidManagedAppProtection.contactSyncBlocked)"
                    Write-Host "Printing blocked: $($AndroidManagedAppProtection.printblocked)"
                    Write-Host
                    write-host "-------------------------------------------------------------------"
                    write-host

                    }

                }

            }

        }

        # If iOS Managed App Policy

        elseif($ManagedAppPolicy.'@odata.type' -eq "#microsoft.graph.iosManagedAppProtection"){

            $iOSManagedAppProtection = Get-ManagedAppProtection -id $ManagedAppPolicy.id -OS "iOS"

            $MAMApps = $iOSManagedAppProtection.apps

            $iOSAssignments = ($iOSManagedAppProtection | select assignments).assignments

            if($iOSAssignments){

                foreach($Group in $iOSAssignments.target){

                    if($AADGroups.id -contains $Group.groupId){

                    $AssignmentCount++

                    $GroupID = $Group.GroupId
                    $GroupTargetType = $Group.'@odata.type'.split(".")[-1]

                    $targetedAppManagementLevels = $iOSManagedAppProtection.targetedAppManagementLevels

                        switch ($targetedAppManagementLevels){

                            "unspecified" {$ManagementType = "All app types";break}
                            "mdm" {$ManagementType = "Apps on managed devices";break}
                            "unmanaged" {$ManagementType = "Apps on unmanaged devices";break}

                            }

                    write-host "Policy name: " -NoNewline
                    write-host $iOSManagedAppProtection.displayname -ForegroundColor Green
                    write-host "Group assigned: " -NoNewline
                    write-host (get-aadgroup -id $GroupID).displayname

                    if($GroupTargetType -eq "exclusionGroupAssignmentTarget"){

                        Write-Host "Group Target: " -NoNewline
                        Write-Host "Excluded" -ForegroundColor Red

                    }

                    elseif($GroupTargetType -eq "GroupAssignmentTarget"){

                        Write-Host "Group Target: " -NoNewline
                        Write-Host "Included" -ForegroundColor Green

                    }

                    Write-Host
                    Write-Host "Targeted Apps:" -ForegroundColor Yellow

                    foreach($MAMApp in $MAMApps){

                        $AppName = (Get-IntuneMAMApplication -bundleid $MAMApp.mobileAppIdentifier.bundleId).displayName

                        if($AppName){ $AppName }
                        else { $MAMApp.mobileAppIdentifier.bundleId }

                    }

                    Write-Host
                    Write-Host "Configuration Settings:" -ForegroundColor Yellow
                    Write-Host "Targeted management type: $ManagementType"
                    Write-Host "Jailbroken/rooted devices blocked: $($iOSManagedAppProtection.deviceComplianceRequired)"
                    Write-Host "Min OS version: $($iOSManagedAppProtection.minimumRequiredOsVersion)"
                    Write-Host "Allowed device model(s): $($iOSManagedAppProtection.allowedIosDeviceModels)"
                    write-host "Require managed browser: $($iOSManagedAppProtection.managedBrowserToOpenLinksRequired)"
                    Write-Host "Contact sync blocked: $($iOSManagedAppProtection.contactSyncBlocked)"
                    Write-Host "FaceId blocked: $($iOSManagedAppProtection.faceIdBlocked)"
                    Write-Host "Printing blocked: $($iOSManagedAppProtection.printblocked)"
                    Write-Host
                    write-host "-------------------------------------------------------------------"
                    write-host

                    }

                }

            }

        }

    }

    if($AssignmentCount -eq 0){

        Write-Host "No $OS App Protection Policies Assigned..."
        Write-Host
        write-host "-------------------------------------------------------------------"
        write-host

    }

}

else {

    Write-Host "No $OS App Protection Policies Exist..."
    Write-Host
    write-host "-------------------------------------------------------------------"
    write-host

}

#endregion

####################################################

#region App Configuration Policies: Managed Apps

Write-Host "App Configuration Policies: Managed Apps" -ForegroundColor Cyan
Write-Host
write-host "-------------------------------------------------------------------"
Write-Host

$TargetedManagedAppConfigurations = Get-TargetedManagedAppConfigurations

$TMACAssignmentCount = 0

if($TargetedManagedAppConfigurations){

$TMACCount = @($TargetedManagedAppConfigurations).count

    foreach($TargetedManagedAppConfiguration in $TargetedManagedAppConfigurations){

    $PolicyId = $TargetedManagedAppConfiguration.id

    $ManagedAppConfiguration = Get-TargetedManagedAppConfigurations -PolicyId $PolicyId

    $MAMApps = $ManagedAppConfiguration.apps

        if($ManagedAppConfiguration.assignments){

            foreach($group in $ManagedAppConfiguration.assignments){

                if($AADGroups.id -contains $Group.target.GroupId){

                $TMACAssignmentCount++

                $GroupID = $Group.target.GroupId
                $GroupTargetType = $Group.target.'@odata.type'.split(".")[-1]

                write-host "Policy name: " -NoNewline
                write-host $ManagedAppConfiguration.displayname -ForegroundColor Green
                write-host "Group assigned: " -NoNewline
                write-host (get-aadgroup -id $GroupID).displayname

                if($GroupTargetType -eq "exclusionGroupAssignmentTarget"){

                    Write-Host "Group Target: " -NoNewline
                    Write-Host "Excluded" -ForegroundColor Red

                }

                elseif($GroupTargetType -eq "GroupAssignmentTarget"){

                    Write-Host "Group Target: " -NoNewline
                    Write-Host "Included" -ForegroundColor Green

                }

                Write-Host
                Write-Host "Targeted Apps:" -ForegroundColor Yellow

                foreach($MAMApp in $MAMApps){

                    if($MAMApp.mobileAppIdentifier.'@odata.type' -eq "#microsoft.graph.androidMobileAppIdentifier"){

                        $AppName = (Get-IntuneMAMApplication -packageId $MAMApp.mobileAppIdentifier.packageId)

                        if($AppName.'@odata.type' -like "*$OS*"){

                            Write-Host $AppName.displayName "-" $AppName.'@odata.type' -ForegroundColor Green

                        }

                        else {

                            Write-Host $AppName.displayName "-" $AppName.'@odata.type'

                        }

                    }

                    elseif($MAMApp.mobileAppIdentifier.'@odata.type' -eq "#microsoft.graph.iosMobileAppIdentifier"){

                        $AppName = (Get-IntuneMAMApplication -bundleId $MAMApp.mobileAppIdentifier.bundleId)

                        if($AppName.'@odata.type' -like "*$OS*"){

                            Write-Host $AppName.displayName "-" $AppName.'@odata.type' -ForegroundColor Green

                        }

                        else {

                            Write-Host $AppName.displayName "-" $AppName.'@odata.type'

                        }

                    }

                }

                Write-Host
                Write-Host "Configuration Settings:" -ForegroundColor yellow

                $ExcludeGroup = $Group.target.'@odata.type'

                $AppConfigNames = $ManagedAppConfiguration.customsettings

                    foreach($Config in $AppConfigNames){

                        $searchName = $config.name

                        if ($Config.name -like "*.*") {

                        $Name = ($config.name).split(".")[-1]


                        }

                        elseif ($Config.name -like "*_*"){

                        $_appConfigName = ($config.name).replace("_"," ")
                        $Name = (Get-Culture).TextInfo.ToTitleCase($_appConfigName.tolower())

                        }

                        else {

                        $Name = $config.name

                        }

                        $Value = ($TargetedManagedAppConfiguration.customSettings | ? { $_.Name -eq "$searchName" } | select value).value

                        if ($name -like "*ListURLs*"){

                            $value = $Value.replace("|",", ")

                            Write-Host
                            Write-Host "$($Name):" -ForegroundColor Yellow
                            Write-Host $($Value)

                        }

                        else {

                        Write-Host "$($Name): $($Value)"

                        }

                    }

                Write-Host
                write-host "-------------------------------------------------------------------"
                write-host

                }

            }

        }

    }

    if($TMACAssignmentCount -eq 0){

        Write-Host "No $OS App Configuration Policies: Managed Apps Assigned..."
        Write-Host
        write-host "-------------------------------------------------------------------"
        write-host

    }

}

else {

    Write-Host "No $OS App Configuration Policies: Managed Apps Exist..."
    Write-Host
    write-host "-------------------------------------------------------------------"
    write-host

}

#endregion

####################################################

#region App Configuration Policies: Managed Devices

Write-Host "App Configuration Policies: Managed Devices" -ForegroundColor Cyan
Write-Host
write-host "-------------------------------------------------------------------"
Write-Host

$AppConfigurations = Get-MobileAppConfigurations | ? { $_.'@odata.type' -like "*$OS*" }

$MACAssignmentCount = 0

if($AppConfigurations){

    foreach($AppConfiguration in $AppConfigurations){

        if($AppConfiguration.assignments){

            foreach($group in $AppConfiguration.assignments){

                if($AADGroups.id -contains $Group.target.GroupId){

                $MACAssignmentCount++

                $GroupID = $Group.target.GroupId
                $GroupTargetType = $Group.target.'@odata.type'.split(".")[-1]

                write-host "Policy name: " -NoNewline
                write-host $AppConfiguration.displayname -ForegroundColor Green
                write-host "Group assigned: " -NoNewline
                write-host (get-aadgroup -id $GroupID).displayname

                if($GroupTargetType -eq "exclusionGroupAssignmentTarget"){

                    Write-Host "Group Target: " -NoNewline
                    Write-Host "Excluded" -ForegroundColor Red

                }

                elseif($GroupTargetType -eq "GroupAssignmentTarget"){

                    Write-Host "Group Target: " -NoNewline
                    Write-Host "Included" -ForegroundColor Green

                }

                $TargetedApp = Get-IntuneApplication -id $AppConfiguration.targetedMobileApps
                Write-Host
                Write-Host "Targeted Mobile App:" -ForegroundColor Yellow
                Write-Host $TargetedApp.displayName "-" $TargetedApp.'@odata.type'
                Write-Host
                Write-Host "Configuration Settings:" -ForegroundColor yellow

                $ExcludeGroup = $Group.target.'@odata.type'

                $Type = ($AppConfiguration.'@odata.type'.split(".")[2] -creplace '([A-Z\W_]|\d+)(?<![a-z])',' $&').trim()

                if($AppConfiguration.settings){

                    $AppConfigNames = $AppConfiguration.settings

                    foreach($Config in $AppConfigNames){

                        if ($Config.appConfigKey -like "*.*") {

                            if($config.appConfigKey -like "*userChangeAllowed*"){

                            $appConfigKey = ($config.appConfigKey).split(".")[-2,-1]
                            $appConfigKey = $($appConfigKey)[-2] + " - " + $($appConfigKey)[-1]

                            }

                            else {

                            $appConfigKey = ($config.appConfigKey).split(".")[-1]

                            }

                        }

                        elseif ($Config.appConfigKey -like "*_*"){

                        $appConfigKey = ($config.appConfigKey).replace("_"," ")

                        }

                        else {

                        $appConfigKey = ($config.appConfigKey)

                        }

                        Write-Host "$($appConfigKey): $($config.appConfigKeyValue)"

                    }

                }

                elseif($AppConfiguration.payloadJson){

                    $JSON = $AppConfiguration.payloadJson

                    $Configs = ([System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String("$JSON")) | ConvertFrom-Json | select managedproperty).managedproperty

                    foreach($Config in $Configs){

                        if ($Config.key -like "*.*") {

                        $appConfigKey = ($config.key).split(".")[-1]

                        }

                        elseif ($Config.key -like "*_*"){

                        $_appConfigKey = ($config.key).replace("_"," ")
                        $appConfigKey = (Get-Culture).TextInfo.ToTitleCase($_appConfigKey.tolower())

                        }

                        Write-Host "$($appConfigKey): $($Config.valueString)$($Config.valueBool)"

                    }

                }

                Write-Host
                write-host "-------------------------------------------------------------------"
                write-host

                }

            }

       }

    }

    if($MACAssignmentCount -eq 0){

        Write-Host "No $OS App Configuration Policies: Managed Devices Assigned..."
        Write-Host
        write-host "-------------------------------------------------------------------"
        write-host

    }

}

else {

    Write-Host "No $OS App Configuration Policies: Managed Devices Exist..."
    Write-Host

}

#endregion

####################################################

Write-Host "Evaluation complete..." -ForegroundColor Green
Write-Host
write-host "-------------------------------------------------------------------"
Write-Host

