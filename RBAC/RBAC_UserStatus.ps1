
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
            "DeviceManagementRBAC.Read.All"
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

    function Get-RBACRole {

    <#
    .SYNOPSIS
    This function is used to get RBAC Role Definitions from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any RBAC Role Definitions
    .EXAMPLE
    Get-RBACRole
    Returns any RBAC Role Definitions configured in Intune
    .NOTES
    NAME: Get-RBACRole
    #>

    $graphApiVersion = "Beta"
    $Resource = "deviceManagement/roleDefinitions"

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

    function Get-RBACRoleDefinition {

    <#
    .SYNOPSIS
    This function is used to get an RBAC Role Definition from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any RBAC Role Definition
    .EXAMPLE
    Get-RBACRoleDefinition -id $id
    Returns an RBAC Role Definitions configured in Intune
    .NOTES
    NAME: Get-RBACRoleDefinition
    #>

    [cmdletbinding()]

    param
    (
        $id
    )

    $graphApiVersion = "Beta"
    $Resource = "deviceManagement/roleDefinitions('$id')?`$expand=roleassignments"

        try {

            if(!$id){

            write-host "No Role ID was passed to the function, provide an ID variable" -f Red
            break

            }

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            (Invoke-IntuneRestMethod -Uri $uri -Method GET).roleAssignments

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

    function Get-RBACRoleAssignment {

    <#
    .SYNOPSIS
    This function is used to get an RBAC Role Assignment from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any RBAC Role Assignment
    .EXAMPLE
    Get-RBACRoleAssignment -id $id
    Returns an RBAC Role Assignment configured in Intune
    .NOTES
    NAME: Get-RBACRoleAssignment
    #>

    [cmdletbinding()]

    param
    (
        $id
    )

    $graphApiVersion = "Beta"
    $Resource = "deviceManagement/roleAssignments('$id')?`$expand=microsoft.graph.deviceAndAppManagementRoleAssignment/roleScopeTags"

        try {

            if(!$id){

            write-host "No Role Assignment ID was passed to the function, provide an ID variable" -f Red
            break

            }

            $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)"
            (Invoke-IntuneRestMethod -Uri $uri -Method GET)

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
    write-host "Please specify the User Principal Name you want to query:" -f Yellow
    $UPN = Read-Host

        if($null -eq $UPN -or "" -eq $UPN){

        Write-Host "Valid UPN not specified, script can't continue..." -f Red
        Write-Host
        break

        }

    $User = Get-AADUser -userPrincipalName $UPN

    $UserID = $User.id
    $UserDN = $User.displayName
    $UserPN = $User.userPrincipalName

    Write-Host
    write-host "-------------------------------------------------------------------"
    write-host
    write-host "Display Name:"$User.displayName
    write-host "User ID:"$User.id
    write-host "User Principal Name:"$User.userPrincipalName
    write-host

    ####################################################

    $MemberOf = Get-AADUser -userPrincipalName $UPN -Property MemberOf

    $DirectoryRole = $MemberOf | ? { $_.'@odata.type' -eq "#microsoft.graph.directoryRole" }

        if($DirectoryRole){

        $DirRole = $DirectoryRole.displayName

        write-host "Directory Role:" -f Yellow
        $DirectoryRole.displayName
        write-host

        }

        else {

        write-host "Directory Role:" -f Yellow
        Write-Host "User"
        write-host

        }

    ####################################################

    $AADGroups = $MemberOf | ? { $_.'@odata.type' -eq "#microsoft.graph.group" } | sort displayName

        if($AADGroups){

        write-host "AAD Group Membership:" -f Yellow

            foreach($AADGroup in $AADGroups){

            $GroupDN = (Get-AADGroup -id $AADGroup.id).displayName

            $GroupDN

            }

        write-host

        }

        else {

        write-host "AAD Group Membership:" -f Yellow
        write-host "No Group Membership in AAD Groups"
        Write-Host

        }

    ####################################################

    write-host "-------------------------------------------------------------------"

    # Getting all Intune Roles defined
    $RBAC_Roles = Get-RBACRole

    $UserRoleCount = 0

    $Permissions = @()

    # Looping through all Intune Roles defined
    foreach($RBAC_Role in $RBAC_Roles){

    $RBAC_id = $RBAC_Role.id

    $RoleAssignments = Get-RBACRoleDefinition -id $RBAC_id

        # If an Intune Role has an Assignment check if the user is a member of members group
        if($RoleAssignments){

            $RoleAssignments | foreach {

            $RBAC_Role_Assignments = $_.id

            $Assignment = Get-RBACRoleAssignment -id $RBAC_Role_Assignments

            $RA_Names = @()

            $Members = $Assignment.members
            $ScopeMembers = $Assignment.scopeMembers
            $ScopeTags = $Assignment.roleScopeTags

                $Members | foreach {

                    if($AADGroups.id -contains $_){

                    $RA_Names += (Get-AADGroup -id $_).displayName

                    }

                }

                if($RA_Names){

                $UserRoleCount++

                Write-Host
                write-host "RBAC Role Assigned: " $RBAC_Role.displayName -ForegroundColor Cyan
                $Permissions += $RBAC_Role.permissions.actions
                Write-Host

                write-host "Assignment Display Name:" $Assignment.displayName -ForegroundColor Yellow
                Write-Host

                Write-Host "Assignment - Members:" -f Yellow
                $RA_Names

                Write-Host
                Write-Host "Assignment - Scope (Groups):" -f Yellow

                    if($Assignment.scopeType -eq "resourceScope"){

                        $ScopeMembers | foreach {

                        (Get-AADGroup -id $_).displayName

                        }

                    }

                    else {

                        Write-Host ($Assignment.ScopeType -creplace  '([A-Z\W_]|\d+)(?<![a-z])',' $&').trim()

                    }

                Write-Host
                Write-Host "Assignment - Scope Tags:" -f Yellow

                    if($ScopeTags){

                        $AllScopeTags += $ScopeTags

                        $ScopeTags | foreach {

                            $_.displayName

                        }

                    }

                    else {

                        Write-Host "No Scope Tag Assigned to the Role Assignment..." -f Red

                    }

                Write-Host
                Write-Host "Assignment - Permissions:" -f Yellow

                $RolePermissions = $RBAC_Role.permissions.actions | foreach { $_.replace("Microsoft.Intune_","") }

                $RolePermissions | sort

                $ScopeTagPermissions += $RolePermissions | foreach { $_.split("_")[0] } | select -Unique | sort

                Write-Host
                write-host "-------------------------------------------------------------------"

                }

            }

        }

    }

    ####################################################

    if($Permissions){

    Write-Host
    write-host "Effective Permissions for user:" -ForegroundColor Yellow

    $Permissions = $Permissions | foreach { $_.replace("Microsoft.Intune_","") }

    $Permissions | select -Unique | sort

    }

    else {

    Write-Host
    write-host "User isn't part of any Intune Roles..." -ForegroundColor Yellow

    }

    Write-Host


    ####################################################


