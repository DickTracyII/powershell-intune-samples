
<#
  Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

<#

.SYNOPSIS
  Name: Configure-MDATPIntuneSecAdminRole.ps1
  Configures MDATP Intune environment by creating a custom role and assignment with permissions to read security baseline data and machine onboarding data.

.DESCRIPTION
  Configures MDATP Intune environment by creating a custom role and assignment with permissions to read security baseline data and machine onboarding data.
  Populates the role assignment with security groups provided by the SecurityGroupList parameter.
  Any users or groups added to the new role assignment will inherit the permissions of the role and gain read access to security baseline data and machine onboarding data.
  Use an elevated command prompt (run as local admin) from a machine with access to your Microsoft Defender ATP environment.
  The script needs to run as local admin to install the Azure AD PowerShell module if not already present.

.PARAMETER AdminUser
  User with global admin privileges in your Intune environment

.PARAMETER SecAdminGroup
  Security group name - Security group that contains SecAdmin users. Supports only one group. Create a group first if needed. Specify SecAdminGroup param or SecurityGroupList param, but not both.

.PARAMETER SecurityGroupList
  Path to txt file containing list of ObjectIds for security groups to add to Intune role. One ObjectId per line. Specify SecAdminGroup param or SecurityGroupList param, but not both.

.EXAMPLE
  Configure-MDATPIntuneSecAdminRole.ps1 -AdminUser admin@tenant.onmicrosoft.com -SecAdminGroup MySecAdminGroup
  Connects to Azure Active Directory environment myMDATP.mydomain.com, creates a custom role with permission to read security baseline data, and populates it with the specified SecAdmin security group

.EXAMPLE
  Configure-MDATPIntuneSecAdminRole.ps1 -AdminUser admin@tenant.onmicrosoft.com -SecurityGroupList .\SecurityGroupList.txt
  Connects to Azure Active Directory environment myMDATP.mydomain.com, creates a custom role with permission to read security baseline data, and populates it with security groups from SecurityGroupList.txt
  SecurityGroupList txt file must contain list of ObjectIds for security groups to add to Intune role. One ObjectId per line.

.NOTES
  This script uses functions provided by Microsoft Graph team:
  Microsoft Graph API's for Intune: https://developer.microsoft.com/en-us/graph/docs/api-reference/beta/resources/intune_graph_overview
  Sample PowerShell Scripts: https://github.com/microsoftgraph/powershell-intune-samples
  https://github.com/microsoftgraph/powershell-intune-samples/tree/master/RBAC

#>

[CmdletBinding()]

Param(

    [Parameter(Mandatory=$true, HelpMessage="AdminUser@myenvironment.onmicrosoft.com")]
    $AdminUser,

    [Parameter(Mandatory=$false, HelpMessage="MySecAdminGroup")]
    [string]$SecAdminGroup,

    [Parameter(Mandatory=$false, HelpMessage="c:\mylist.txt")]
    $SecurityGroupList

)


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
# Parameters
####################################################

if ($SecurityGroupList){

    $SecurityGroupList = Get-Content "$SecurityGroupList"

}

$AADEnvironment = (New-Object "System.Net.Mail.MailAddress" -ArgumentList $AdminUser).Host

$RBACRoleName    = "MDATP SecAdmin"
$SecurityGroup   = "MDATP SecAdmin SG"
$User = $AdminUser

####################################################
# Functions
####################################################


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
NAME: Test-JSON
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
              Write-Host

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
  Write-Host
  break

  }

}

####################################################

function Add-RBACRole {

<#
.SYNOPSIS
This function is used to add an RBAC Role Definitions from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and adds an RBAC Role Definitions
.EXAMPLE
Add-RBACRole -JSON $JSON
.NOTES
NAME: Add-RBACRole
#>

[cmdletbinding()]

param
(
    $JSON
)

$graphApiVersion = "Beta"
$Resource = "deviceManagement/roleDefinitions"

    try {

        if(!$JSON){

        Write-Host "No JSON was passed to the function, provide a JSON variable" -f Red
        break

        }

        Test-JSON -JSON $JSON

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
    Write-Host
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

  [cmdletbinding()]

  param
  (
      $Name
  )

  $graphApiVersion = "v1.0"
  $Resource = "deviceManagement/roleDefinitions"

      try {

        if($Name){
          $QueryString = "?`$filter=contains(displayName, '$Name')"
          $uri = "$global:GraphEndpoint/$graphApiVersion/$($Resource)$($QueryString)"
          $rbacRoles = (Invoke-IntuneRestMethod -Uri $uri -Method GET).Value
          $customRbacRoles = $rbacRoles | Where-Object { $_isBuiltInRoleDefinition -eq $false }
          return $customRbacRoles
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
      Write-Host
      break

      }

}

####################################################

function Assign-RBACRole {

<#
.SYNOPSIS
This function is used to set an assignment for an RBAC Role using the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and sets and assignment for an RBAC Role
.EXAMPLE
Assign-RBACRole -Id $IntuneRoleID -DisplayName "Assignment" -MemberGroupId $MemberGroupId -TargetGroupId $TargetGroupId
Creates and Assigns and Intune Role assignment to an Intune Role in Intune
.NOTES
NAME: Assign-RBACRole
#>

[cmdletbinding()]

param
(
    $Id,
    $DisplayName,
    $MemberGroupId,
    $TargetGroupId
)

$graphApiVersion = "Beta"
$Resource = "deviceManagement/roleAssignments"

    try {

        if(!$Id){

        Write-Host "No Policy Id specified, specify a valid Application Id" -f Red
        break

        }

        if(!$DisplayName){

        Write-Host "No Display Name specified, specify a Display Name" -f Red
        break

        }

        if(!$MemberGroupId){

        Write-Host "No Member Group Id specified, specify a valid Target Group Id" -f Red
        break

        }

        if(!$TargetGroupId){

        Write-Host "No Target Group Id specified, specify a valid Target Group Id" -f Red
        break

        }


$JSON = @"
    {
    "id":"",
    "description":"",
    "displayName":"$DisplayName",
    "members":["$MemberGroupId"],
    "scopeMembers":["$TargetGroupId"],
    "roleDefinition@odata.bind":"beta/deviceManagement/roleDefinitions('$ID')"
    }
"@

    $uri = "$global:GraphEndpoint/$graphApiVersion/$Resource"
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
    Write-Host
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

$JSON = @"
{
  "@odata.type": "#microsoft.graph.roleDefinition",
  "displayName": "$RBACRoleName",
  "description": "Role with access to modify Intune SecuriyBaselines and DeviceConfigurations",
  "permissions": [
    {
      "actions": [
        "Microsoft.Intune_Organization_Read",
        "Microsoft.Intune/SecurityBaselines/Assign",
        "Microsoft.Intune/SecurityBaselines/Create",
        "Microsoft.Intune/SecurityBaselines/Delete",
        "Microsoft.Intune/SecurityBaselines/Read",
        "Microsoft.Intune/SecurityBaselines/Update",
        "Microsoft.Intune/DeviceConfigurations/Assign",
        "Microsoft.Intune/DeviceConfigurations/Create",
        "Microsoft.Intune/DeviceConfigurations/Delete",
        "Microsoft.Intune/DeviceConfigurations/Read",
        "Microsoft.Intune/DeviceConfigurations/Update"
      ]
    }
  ],
  "isBuiltInRoleDefinition": false
}
"@

####################################################
# Main
####################################################

Write-Host "Configuring MDATP Intune SecAdmin Role..." -ForegroundColor Cyan
Write-Host
Write-Host "Connecting to Azure AD environment: $AADEnvironment..." -ForegroundColor Yellow
Write-Host

$RBAC_Roles = Get-RBACRole

# Checking if Intune Role already exist with $RBACRoleName
if($RBAC_Roles | Where-Object { $_.displayName -eq "$RBACRoleName" }){

    Write-Host "Intune Role already exists with name '$RBACRoleName'..." -ForegroundColor Red
    Write-Host "Script can't continue..." -ForegroundColor Red
    Write-Host
    break

}

# Add new RBAC Role
Write-Host "Adding new RBAC Role: $RBACRoleName..." -ForegroundColor Yellow
Write-Host "JSON:"
Write-Host $JSON
Write-Host

$NewRBACRole = Add-RBACRole -JSON $JSON
$NewRBACRoleID = $NewRBACRole.id

# Get Id for new Role
Write-Host "Getting Id for new role..." -ForegroundColor Yellow
$Updated_RBAC_Roles = Get-RBACRole

$NewRBACRoleID = ($Updated_RBAC_Roles | Where-Object {$_.displayName -eq "$RBACRoleName"}).id

Write-Host "$NewRBACRoleID"
Write-Host

####################################################

if($SecAdminGroup){

  # Verify group exists
  Write-Host "Verifying group '$SecAdminGroup' exists..." -ForegroundColor Yellow

  Connect-AzureAD -AzureEnvironmentName AzureCloud -AccountId $AdminUser | Out-Null
  $ValidatedSecAdminGroup = (Get-AzureADGroup -SearchString $SecAdminGroup).ObjectId

  if ($ValidatedSecAdminGroup){

    Write-Host "AAD Group '$SecAdminGroup' exists" -ForegroundColor Green
    Write-Host ""
    Write-Host "Adding AAD group $SecAdminGroup - $ValidatedSecAdminGroup to MDATP Role..." -ForegroundColor Yellow

    # Verify security group list only contains valid GUIDs
    try {

      [System.Guid]::Parse($ValidatedSecAdminGroup) | Out-Null
      Write-Host "ObjectId: $ValidatedSecAdminGroup" -ForegroundColor Green
      Write-Host

    }

    catch {

        Write-Host "ObjectId: $ValidatedSecAdminGroup is not a valid ObjectId" -ForegroundColor Red
        Write-Host "Verify that your security group list only contains valid ObjectIds and try again." -ForegroundColor Cyan
        exit -1

    }

  Write-Host "Adding security group to RBAC role $RBACRoleName ..." -ForegroundColor Yellow

  Assign-RBACRole -Id $NewRBACRoleID -DisplayName 'MDATP RBAC Assignment' -MemberGroupId $ValidatedSecAdminGroup -TargetGroupId "default"
  # NOTE: TargetGroupID = Scope Group

  }

  else {

    Write-Host "Group '$SecAdminGroup' does not exist. Please run script again and specify a valid group." -ForegroundColor Red
    Write-Host
    break

  }

}

####################################################

if($SecurityGroupList){

  Write-Host "Validating Security Groups to add to Intune Role:" -ForegroundColor Yellow

  foreach ($SecurityGroup in $SecurityGroupList) {

    # Verify security group list only contains valid GUIDs
    try {

      [System.Guid]::Parse($SecurityGroup) | Out-Null
      Write-Host "ObjectId: $SecurityGroup" -ForegroundColor Green

    }

    catch {

        Write-Host "ObjectId: $SecurityGroup is not a valid ObjectId" -ForegroundColor Red
        Write-Host "Verify that your security group list only contains valid ObjectIds and try again." -ForegroundColor Cyan
        exit -1

    }

  }

  # Format list for Assign-RBACRole function
  $ValidatedSecurityGroupList = $SecurityGroupList -join "`",`""

  $SecurityGroupList
  $ValidatedSecurityGroupList

  Write-Host ""
  Write-Host "Adding security groups to RBAC role '$RBACRoleName'..." -ForegroundColor Yellow

  Assign-RBACRole -Id $NewRBACRoleID -DisplayName 'MDATP RBAC Assignment' -MemberGroupId $ValidatedSecurityGroupList -TargetGroupId "default"
  # NOTE: TargetGroupID = Scope Group

}

####################################################

Write-Host "Retrieving permissions for new role: $RBACRoleName..." -ForegroundColor Yellow
Write-Host

$RBAC_Role = Get-RBACRole | Where-Object { $_.displayName -eq "$RBACRoleName" }

Write-Host $RBAC_Role.displayName -ForegroundColor Green
Write-Host $RBAC_Role.id -ForegroundColor Cyan
$RBAC_Role.RolePermissions.resourceActions.allowedResourceActions
Write-Host

####################################################

Write-Host "Members of RBAC Role '$RBACRoleName' should now have access to Security Baseline and" -ForegroundColor Cyan
write-host "Onboarded machines tiles in Microsoft Defender Security Center." -ForegroundColor Cyan
Write-Host
Write-Host "https://securitycenter.windows.com/configuration-management"
Write-Host
Write-Host "Add users and groups to the new role assignment 'MDATP RBAC Assignment' as needed." -ForegroundColor Cyan

Write-Host
Write-Host "Configuration of MDATP Intune SecAdmin Role complete..." -ForegroundColor Green
Write-Host

