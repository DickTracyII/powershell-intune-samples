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

function Get-AADGroups {

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
$graphApiVersion = "beta"
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

function Get-DeviceCompliancePolicy {

<#
.SYNOPSIS
This function is used to get device compliance policies from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any device compliance policies
.EXAMPLE
Get-DeviceCompliancePolicy
Returns any device compliance policies configured in Intune
.EXAMPLE
Get-DeviceCompliancePolicy -Android
Returns any device compliance policies for Android configured in Intune
.EXAMPLE
Get-DeviceCompliancePolicy -iOS
Returns any device compliance policies for iOS configured in Intune
.NOTES
NAME: Get-DeviceCompliancePolicy
#>

[cmdletbinding()]

param
(
    $Name,
    [Parameter(HelpMessage = "Compliance Platform")]
    [ValidateSet("Android","iOS","Windows10","AndroidEnterprise","macOS")]
    $Platform

)

$graphApiVersion = "Beta"
$Resource = "deviceManagement/deviceCompliancePolicies?`$expand=assignments"

    try {


        if($Platform -eq "Android"){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'@odata.type').contains("android") }

        }

        elseif($Platform -eq "iOS"){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'@odata.type').contains("ios") }

        }

        elseif($Platform -eq "Windows10"){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'@odata.type').contains("windows10CompliancePolicy") }

        }

        elseif($Name){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'displayName').contains("$Name") }

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

function Get-DeviceConfigurationPolicy {

<#
.SYNOPSIS
This function is used to get device configuration policies from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any device configuration policies
.EXAMPLE
Get-DeviceConfigurationPolicy
Returns any device configuration policies configured in Intune
.NOTES
NAME: Get-DeviceConfigurationPolicy
#>

[cmdletbinding()]

param
(
    $name
)

$graphApiVersion = "Beta"
$DCP_resource = "deviceManagement/deviceConfigurations?`$expand=assignments"

    try {

        if($Name){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($DCP_resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'displayName').contains("$Name") }

        }

        else {

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($DCP_resource)"
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

function Get-AdministrativeTemplates {

<#
.SYNOPSIS
This function is used to get Administrative Templates from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any Administrative Templates
.EXAMPLE
Get-AdministrativeTemplates
Returns any Administrative Templates configured in Intune
.NOTES
NAME: Get-AdministrativeTemplates
#>

[cmdletbinding()]

param
(
    $name
)

$graphApiVersion = "beta"
$Resource = "deviceManagement/groupPolicyConfigurations?`$expand=assignments"

    try {

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
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

function Get-AssignmentFilters {

<#
.SYNOPSIS
This function is used to get assignment filters from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any assignment filters
.EXAMPLE
Get-AssignmentFilters
Returns any assignment filters configured in Intune
.NOTES
NAME: Get-AssignmentFilters
#>

[cmdletbinding()]

param
(
    $name
)

$graphApiVersion = "beta"
$Resource = "deviceManagement/assignmentFilters"

    try {

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
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

function Get-SettingsCatalogPolicy {

<#
.SYNOPSIS
This function is used to get Settings Catalog policies from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any Settings Catalog policies
.EXAMPLE
Get-SettingsCatalogPolicy
Returns any Settings Catalog policies configured in Intune
Get-SettingsCatalogPolicy -Platform windows10
Returns any Windows 10 Settings Catalog policies configured in Intune
Get-SettingsCatalogPolicy -Platform macOS
Returns any MacOS Settings Catalog policies configured in Intune
.NOTES
NAME: Get-SettingsCatalogPolicy
#>

[cmdletbinding()]

param
(
    [parameter(Mandatory=$false)]
    [ValidateSet("windows10","macOS")]
    [ValidateNotNullOrEmpty()]
    [string]$Platform,
    [parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    $id
)

$graphApiVersion = "beta"

    if($Platform){

        $Resource = "deviceManagement/configurationPolicies?`$filter=platforms has '$Platform' and technologies has 'mdm'"

    }

    elseif($id){

        $Resource = "deviceManagement/configurationPolicies('$id')/assignments"

    }

    else {

        $Resource = "deviceManagement/configurationPolicies?`$filter=technologies has 'mdm'"

    }

    try {

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
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
    $Name
)

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/mobileApps?`$expand=assignments"

    try {

        if($Name){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'displayName').contains("$Name") -and (!($_.'@odata.type').Contains("managed")) -and (!($_.'@odata.type').Contains("#microsoft.graph.iosVppApp")) }

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

#region Authentication

# Connect to Microsoft Graph
if (-not (Connect-GraphAPI)) {
    Write-Error "Failed to connect to Microsoft Graph. Exiting script."
    exit 1
}

#endregion

####################################################

write-host "Filters Name:" -f Yellow
$FilterName = Read-Host

if($null -eq $FilterName -or "" -eq $FilterName){

    write-host "Filter Name is Null..." -ForegroundColor Red
    Write-Host "Script can't continue..." -ForegroundColor Red
    Write-Host
    break

}

####################################################

$Filters = Get-AssignmentFilters

$Filter = $Filters | ? { $_.displayName -eq "$FilterName" }

if(!$Filter){

    Write-Host
    Write-Host "Filter with Name '$FilterName' doesn't exist..." -ForegroundColor Red
    Write-Host "Script can't continue..." -ForegroundColor Red
    Write-Host
    break

}

if($Filter.count -gt 1){

    Write-Host
    Write-Host "There are multiple filters with the same display name '$FilterName', unique names should be used..." -ForegroundColor Red
    Write-Host "Script can't continue..." -ForegroundColor Red
    Write-Host
    break

}

Write-Host
write-host "-------------------------------------------------------------------"
Write-Host
Write-Host "Filter found..." -f Green
Write-Host "Filter Id:       " $Filter.id
Write-Host "Filter Name:     " $Filter.displayName
Write-Host "Filter Platform: " $Filter.platform
Write-Host "Filter Rule:     " $filter.rule
Write-Host "Filter Scope Tag:" $filter.roleScopeTags
Write-Host

####################################################

$Activity = "Filter Usage Check"

####################################################

#region CompliancePolicies

$CPs = Get-DeviceCompliancePolicy

write-host "-------------------------------------------------------------------"
write-host "Device Compliance Policies" -f Cyan
write-host "-------------------------------------------------------------------"

if(@($CPs).count -ge 1){

    $CPCount = @($CPs).count
    $i = 1

    $CP_Count = 0

    foreach($CP in $CPs){

    $id = $CP.id

    $DCPA = $CP.assignments

        if($DCPA){

            foreach($Com_Group in $DCPA){

                if($Com_Group.target.deviceAndAppManagementAssignmentFilterId -eq $Filter.id){

                    Write-Host
                    Write-Host "Policy Name: " -NoNewline
                    Write-Host $CP.displayName -f green
                    Write-Host "Filter Type:" $Com_Group.target.deviceAndAppManagementAssignmentFilterType

                    if($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allDevicesAssignmentTarget"){

                        Write-Host "AAD Group Name: All Devices"

                    }

                    elseif($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allLicensedUsersAssignmentTarget"){

                        Write-Host "AAD Group Name: All Users"

                    }

                    else {

                        Write-Host "AAD Group Name:" (Get-AADGroups -id $Com_Group.target.groupId).displayName

                    }

                    Write-Host
                    $CP_Count++

                }

            }

        }

        Write-Progress -Activity "$Activity" -status "Checking Device Compliance Policy $i of $CPCount" `
        -percentComplete ($i / $CPCount*100)
        $i++

    }

    Write-Progress -Completed -Activity "$Activity"

    if($CP_Count -eq 0){

        Write-Host
        Write-Host "Filter '$FilterName' not used..." -ForegroundColor Yellow
        Write-Host

    }

}

else {

Write-Host
write-host "No Device Compliance Policies Found..." -f Red
write-host

}

#endregion

####################################################

#region ConfigurationPolicies

$DCPs = Get-DeviceConfigurationPolicy

write-host "-------------------------------------------------------------------"
write-host "Device Configuration Policies" -f Cyan
write-host "-------------------------------------------------------------------"

if($DCPs){

    $DCPsCount = @($DCPs).count
    $i = 1

    $DCP_Count = 0

    foreach($DCP in $DCPs){

    $id = $DCP.id

    $CPA = $DCP.assignments

        if($CPA){

            foreach($Com_Group in $CPA){

                if($Com_Group.target.deviceAndAppManagementAssignmentFilterId -eq $Filter.id){

                    Write-Host
                    Write-Host "Policy Name: " -NoNewline
                    Write-Host $DCP.displayName -f green
                    Write-Host "Filter Type:" $Com_Group.target.deviceAndAppManagementAssignmentFilterType

                    if($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allDevicesAssignmentTarget"){

                        Write-Host "AAD Group Name: All Devices"

                    }

                    elseif($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allLicensedUsersAssignmentTarget"){

                        Write-Host "AAD Group Name: All Users"

                    }

                    else {

                        Write-Host "AAD Group Name:" (Get-AADGroups -id $Com_Group.target.groupId).displayName

                    }

                    Write-Host
                    $DCP_Count++

                }


            }

        }

        Write-Progress -Activity "$Activity" -status "Checking Device Configuration Policy $i of $DCPsCount" `
        -percentComplete ($i / $DCPsCount*100)
        $i++

    }

    Write-Progress -Completed -Activity "$Activity"

    if($DCP_Count -eq 0){

        Write-Host
        Write-Host "Filter '$FilterName' not used..." -ForegroundColor Yellow
        Write-Host

    }

}

else {

    Write-Host
    write-host "No Device Configuration Policies Found..."
    Write-Host

}

#endregion

####################################################

#region SettingsCatalog

$SCPolicies = Get-SettingsCatalogPolicy

write-host "-------------------------------------------------------------------"
write-host "Settings Catalog Policies" -f Cyan
write-host "-------------------------------------------------------------------"

if($SCPolicies){

    $SCPCount = @($SCPolicies).count
    $i = 1

    $SC_Count = 0

    foreach($SCPolicy in $SCPolicies){

    $id = $SCPolicy.id

    $SCPolicyAssignment = Get-SettingsCatalogPolicy -id $id

        if($SCPolicyAssignment){

            foreach($Com_Group in $SCPolicyAssignment){

                if($Com_Group.target.deviceAndAppManagementAssignmentFilterId -eq $Filter.id){

                    Write-Host
                    Write-Host "Policy Name: " -NoNewline
                    Write-Host $SCPolicy.name -f green
                    Write-Host "Filter Type:" $Com_Group.target.deviceAndAppManagementAssignmentFilterType

                    if($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allDevicesAssignmentTarget"){

                        Write-Host "AAD Group Name: All Devices"

                    }

                    elseif($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allLicensedUsersAssignmentTarget"){

                        Write-Host "AAD Group Name: All Users"

                    }

                    else {

                        Write-Host "AAD Group Name:" (Get-AADGroups -id $Com_Group.target.groupId).displayName

                    }

                    Write-Host
                    $SC_Count++

                }

            }

        }

        Write-Progress -Activity "$Activity" -status "Checking Settings Catalog $i of $SCPCount" `
        -percentComplete ($i / $SCPCount*100)
        $i++

    }

    Write-Progress -Completed -Activity "$Activity"

    if($SC_Count -eq 0){

        Write-Host
        Write-Host "Filter '$FilterName' not used..." -ForegroundColor Yellow
        Write-Host

    }

}

else {

    write-host
    write-host "No Settings Catalog Policies Found..."
    Write-Host

}

#endregion

####################################################

#region ADMX Templates

$ADMXPolicies = Get-AdministrativeTemplates

write-host "-------------------------------------------------------------------"
write-host "Administrative Templates Policies" -f Cyan
write-host "-------------------------------------------------------------------"

if($ADMXPolicies){

    $ATCount = @($ADMXPolicies).count
    $i = 1

    $AT_Count = 0

    foreach($ADMXPolicy in $ADMXPolicies){

    $id = $ADMXPolicy.id

    $ATPolicyAssignment = $ADMXPolicy.assignments

        if($ATPolicyAssignment){

            foreach($Com_Group in $ATPolicyAssignment){

                if($Com_Group.target.deviceAndAppManagementAssignmentFilterId -eq $Filter.id){

                    Write-Host
                    Write-Host "Policy Name: " -NoNewline
                    Write-Host $ADMXPolicy.displayName -f green
                    Write-Host "Filter Type:" $Com_Group.target.deviceAndAppManagementAssignmentFilterType

                    if($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allDevicesAssignmentTarget"){

                        Write-Host "AAD Group Name: All Devices"

                    }

                    elseif($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allLicensedUsersAssignmentTarget"){

                        Write-Host "AAD Group Name: All Users"

                    }

                    else {

                        Write-Host "AAD Group Name:" (Get-AADGroups -id $Com_Group.target.groupId).displayName

                    }

                    Write-Host
                    $AT_Count++

                }

            }

        }

        Write-Progress -Activity "$Activity" -status "Checking Administrative Templates Policy $i of $ATCount" `
        -percentComplete ($i / $ATCount*100)
        $i++

    }

    Write-Progress -Completed -Activity "$Activity"

    if($AT_Count -eq 0){

        Write-Host
        Write-Host "Filter '$FilterName' not used..." -ForegroundColor Yellow
        Write-Host

    }

}

else {

Write-Host
write-host "No Administrative Templates Policies Found..."
Write-Host

}

#endregion

####################################################

#region IntuneApplications

$Apps = Get-IntuneApplication

write-host "-------------------------------------------------------------------"
write-host "Intune Applications" -f Cyan
write-host "-------------------------------------------------------------------"

if($Apps){

    $AppsCount = @($Apps).count
    $i = 1

    $App_Count = 0

    foreach($App in $Apps){

    $id = $App.id

    $AppAssignment = $app.assignments

        if($AppAssignment){

            foreach($Com_Group in $AppAssignment){

                if($Com_Group.target.deviceAndAppManagementAssignmentFilterId -eq $Filter.id){

                    Write-Host
                    Write-Host "Application Name: " -NoNewline
                    Write-Host $App.displayName -f green
                    Write-Host "Filter Type:" $Com_Group.target.deviceAndAppManagementAssignmentFilterType

                    if($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allDevicesAssignmentTarget"){

                        Write-Host "AAD Group Name: All Devices"

                    }

                    elseif($Com_Group.target.'@odata.type' -eq "#microsoft.graph.allLicensedUsersAssignmentTarget"){

                        Write-Host "AAD Group Name: All Users"

                    }

                    else {

                        Write-Host "AAD Group Name:" (Get-AADGroups -id $Com_Group.target.groupId).displayName

                    }

                    Write-Host
                    $App_Count++

                }

            }

        }

        Write-Progress -Activity "$Activity" -status "Checking Intune Application $i of $AppsCount" `
        -percentComplete ($i / $AppsCount*100)
        $i++

    }

    Write-Progress -Completed -Activity "$Activity"

    if($App_Count -eq 0){

        Write-Host
        Write-Host "Filter '$FilterName' not used..." -ForegroundColor Yellow
        Write-Host

    }

}

else {

write-host
write-host "No Intune Applications Found..."
Write-Host

}

#endregion

####################################################

write-host "-------------------------------------------------------------------"
Write-Host "Overall Analysis" -ForegroundColor Cyan
write-host "-------------------------------------------------------------------"
Write-Host "Status of each area of MEM that support Filters assignment status"
Write-Host
Write-Host "Applicable OS Type: " -NoNewline
Write-Host $Filter.Platform -ForegroundColor Yellow
Write-Host
Write-Host "Compliance Policies:           " $CP_Count
write-host "Device Configuration Policies: " $DCP_Count
Write-Host "Settings Catalog Policies:     " $SC_Count
Write-Host "Administrative Templates:      " $AT_Count
Write-Host "Intune Applications:           " $App_Count
Write-Host

$CountFilters = $CP_Count + $DCP_Count + $SC_Count + $AT_Count + $App_Count

Write-Host "Total Filters Assigned:" $CountFilters
Write-Host

####################################################

write-host "-------------------------------------------------------------------"
Write-Host "Evaluation complete..." -ForegroundColor Green
write-host "-------------------------------------------------------------------"
Write-Host

