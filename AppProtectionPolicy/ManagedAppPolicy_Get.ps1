
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

function Get-ManagedAppPolicy {

<#
.SYNOPSIS
This function is used to get managed app policies from the Graph API REST interface
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
    $Name
)

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/managedAppPolicies"

    try {

        if($Name){

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'displayName').contains("$Name") }

        }

        else {

        $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
        (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value | Where-Object { ($_.'@odata.type').contains("ManagedAppProtection") -or ($_.'@odata.type').contains("InformationProtectionPolicy") }

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

            write-host "No OS parameter specified, please provide an OS. Supported value are Android,iOS,WIP_WE,WIP_MDM..." -f Red
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

            elseif($OS -eq "WIP_WE"){

            $Resource = "deviceAppManagement/windowsInformationProtectionPolicies('$id')?`$expand=protectedAppLockerFiles,exemptAppLockerFiles,assignments"

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            Invoke-IntuneRestMethod -Uri $uri -Method GET

            }

            elseif($OS -eq "WIP_MDM"){

            $Resource = "deviceAppManagement/mdmWindowsInformationProtectionPolicies('$id')?`$expand=protectedAppLockerFiles,exemptAppLockerFiles,assignments"

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

write-host "Running query against Microsoft Graph for App Protection Policies" -f Yellow

$ManagedAppPolicies = Get-ManagedAppPolicy

write-host

foreach($ManagedAppPolicy in $ManagedAppPolicies){

write-host "Managed App Policy:"$ManagedAppPolicy.displayName -f Yellow

$ManagedAppPolicy

    # If Android Managed App Policy

    if($ManagedAppPolicy.'@odata.type' -eq "#microsoft.graph.androidManagedAppProtection"){

        $AndroidManagedAppProtection = Get-ManagedAppProtection -id $ManagedAppPolicy.id -OS "Android"

        write-host "Managed App Policy - Assignments" -f Cyan

        $AndroidAssignments = ($AndroidManagedAppProtection | select assignments).assignments

            if($AndroidAssignments){

                foreach($Group in $AndroidAssignments.target.groupId){

                (Get-AADGroup -id $Group).displayName

                }

                Write-Host

            }

            else {

            Write-Host "No assignments set for this policy..." -ForegroundColor Red
            Write-Host

            }

        write-host "Managed App Policy - Mobile Apps" -f Cyan

        if($ManagedAppPolicy.deployedAppCount -ge 1){

        ($AndroidManagedAppProtection | select apps).apps.mobileAppIdentifier

        }

        else {

        Write-Host "No Managed Apps targeted..." -ForegroundColor Red
        Write-Host

        }

    }

    # If iOS Managed App Policy

    elseif($ManagedAppPolicy.'@odata.type' -eq "#microsoft.graph.iosManagedAppProtection"){

        $iOSManagedAppProtection = Get-ManagedAppProtection -id $ManagedAppPolicy.id -OS "iOS"

        write-host "Managed App Policy - Assignments" -f Cyan

        $iOSAssignments = ($iOSManagedAppProtection | select assignments).assignments

            if($iOSAssignments){

                foreach($Group in $iOSAssignments.target.groupId){

                (Get-AADGroup -id $Group).displayName

                }

                Write-Host

            }

            else {

            Write-Host "No assignments set for this policy..." -ForegroundColor Red
            Write-Host

            }

        write-host "Managed App Policy - Mobile Apps" -f Cyan

        if($ManagedAppPolicy.deployedAppCount -ge 1){

        ($iOSManagedAppProtection | select apps).apps.mobileAppIdentifier

        }

        else {

        Write-Host "No Managed Apps targeted..." -ForegroundColor Red
        Write-Host

        }

    }

    # If WIP Without Enrollment Managed App Policy

    elseif($ManagedAppPolicy.'@odata.type' -eq "#microsoft.graph.windowsInformationProtectionPolicy"){

        $Win10ManagedAppProtection = Get-ManagedAppProtection -id $ManagedAppPolicy.id -OS "WIP_WE"

        write-host "Managed App Policy - Assignments" -f Cyan

        $Win10Assignments = ($Win10ManagedAppProtection | select assignments).assignments

            if($Win10Assignments){

                foreach($Group in $Win10Assignments.target.groupId){

                (Get-AADGroup -id $Group).displayName

                }

                Write-Host

            }

            else {

            Write-Host "No assignments set for this policy..." -ForegroundColor Red
            Write-Host

            }

        write-host "Protected Apps" -f Cyan

        if($Win10ManagedAppProtection.protectedApps){

        $Win10ManagedAppProtection.protectedApps.displayName

        Write-Host

        }

        else {

        Write-Host "No Protected Apps targeted..." -ForegroundColor Red
        Write-Host

        }


        write-host "Protected AppLocker Files" -ForegroundColor Cyan

        if($Win10ManagedAppProtection.protectedAppLockerFiles){

        $Win10ManagedAppProtection.protectedAppLockerFiles.displayName

        Write-Host

        }

        else {

        Write-Host "No Protected Applocker Files targeted..." -ForegroundColor Red
        Write-Host

        }

    }

    # If WIP with Enrollment (MDM) Managed App Policy

    elseif($ManagedAppPolicy.'@odata.type' -eq "#microsoft.graph.mdmWindowsInformationProtectionPolicy"){

        $Win10ManagedAppProtection = Get-ManagedAppProtection -id $ManagedAppPolicy.id -OS "WIP_MDM"

        write-host "Managed App Policy - Assignments" -f Cyan

        $Win10Assignments = ($Win10ManagedAppProtection | select assignments).assignments

            if($Win10Assignments){

                foreach($Group in $Win10Assignments.target.groupId){

                (Get-AADGroup -id $Group).displayName

                }

                Write-Host

            }

            else {

            Write-Host "No assignments set for this policy..." -ForegroundColor Red
            Write-Host

            }

        write-host "Protected Apps" -f Cyan

        if($Win10ManagedAppProtection.protectedApps){

        $Win10ManagedAppProtection.protectedApps.displayName

        Write-Host

        }

        else {

        Write-Host "No Protected Apps targeted..." -ForegroundColor Red
        Write-Host

        }


        write-host "Protected AppLocker Files" -ForegroundColor Cyan

        if($Win10ManagedAppProtection.protectedAppLockerFiles){

        $Win10ManagedAppProtection.protectedAppLockerFiles.displayName

        Write-Host

        }

        else {

        Write-Host "No Protected Applocker Files targeted..." -ForegroundColor Red
        Write-Host

        }

    }

}

