If you use legacy authentication methods or the deprecated ClientID "**d1ddf0e4-d672-4dae-b554-9d5bdfd93547"** in your PowerShell scripts, you need to update to use the modern Microsoft.Graph.Authentication module with **Connect-MgGraph**. if your using "**Connect-msgraph**" or use the ClientID “**d1ddf0e4-d672-4dae-b554-9d5bdfd93547”** in your PowerShell scripts, you need to update your ClientID.

Option 1: Migrate your existing application to use the SDK's _Microsoft.Graph.Authentication_ module. [Update to Microsoft Graph PowerShell SDK - Microsoft Graph | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation?view=graph-powershell-1.0)

Option 2: Register a new app in Entra ID and configure it for Microsoft Graph access:

[Quickstart: Register an app in the Microsoft identity platform - Microsoft identity platform | Microsoft Learn](https://learn.microsoft.com/en-au/entra/identity-platform/quickstart-register-app)

**Steps to register Application in Entra ID to access Intune data via Graph API:**

1\. Login to **Portal.Azure.com,** select Entra ID> App registrations and click "New registration"  
<br/>2\. Enter a display name for the application and select the supported account type. Typically this will be "Accounts in this organizational directory only". This means your application is only used by users (or guests) in your tenant. For Platform, select "Public client/native (mobile & desktop)". Enter the redirect Url "**urn:ietf:wg:oauth:2.0:oob**" Then, click register.

3\. Select the App Registration page, choose your app, then click “API permissions”>"+Add a permission"> "Microsoft Graph"

4\. There are two types of permissions "Delegated permissions" and "Application permissions. For more information about permissions, see

[Overview of permissions and consent in the Microsoft identity platform - Microsoft identity platform | Microsoft Learn](https://learn.microsoft.com/en-us/entra/identity-platform/permissions-consent-overview)

| Permission types | Delegated permissions | Application permissions |
| --- | --- | --- |
| Types of apps | Web / Mobile / single-page app (SPA) | Web / Daemon |
| Access context | Get access on behalf of a user | Get access without a user |
| Who can consent | \- Users can consent for their data  <br>\- Admins can consent for all users | Only admin can consent |
| Consent methods | \- Static: configured list on app registration  <br>\- Dynamic: request individual permissions at login | \- Static ONLY: configured list on app registration |

For this example, we use delegated permission and assign needed permissions to this application. Intune permissions start with DeviceManagement\*. Select the checkbox next to the required permissions, then click add permission. You need to identify the permissions required for your script actions.  It is recommended to use Read permissions if your script does not make any changes in Intune.  For example, if your script reads application information, add the DeviceManagementApps.Read.All permission.

5\. Click "Grant admin consent for &lt;companyname&gt;"

6\. To use your new Application ID, select the "Overview" page and copy your application ID. We need this id to tell our script to access it.

7\. Optional step. If your script runs with app-only authentication you need to request secrets. Click Certificates & Secrets and select New client secret. Add a Description and choose an expiration duration. Click Add to create the new client secret. Copy the client secret so it can be used by your application. It can only be viewed at creation time.

Your App registration is done.

To modify your PowerShell scripts:

**Using the Microsoft.Graph.Authentication Module (Recommended)**

Install the Microsoft Graph PowerShell SDK if not already installed:
```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

**For Delegated Authentication (Interactive Login):**
```powershell
# Connect interactively
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All", "DeviceManagementApps.ReadWrite.All"

# Verify connection
Get-MgContext
```

**For Application Authentication (Client Credentials):**
```powershell
# Define the Tenant ID, Client ID, and Client Secret
$TenantId = "your-tenant-id"
$ClientId = "your-client-id"
$ClientSecret = "your-client-secret"

# Convert the Client Secret to a Secure String
$SecureClientSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force

# Create a PSCredential object
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $SecureClientSecret

# Connect to Microsoft Graph using the Tenant ID and Client Secret Credential
Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential

# Verify connection
Get-MgContext
```

**For Certificate-Based Authentication:**
```powershell
# Connect using certificate thumbprint
Connect-MgGraph -ClientId "your-client-id" -TenantId "your-tenant-id" -CertificateThumbprint "your-cert-thumbprint"
```

**Legacy Methods (Deprecated - Update Required)**

~~The following methods are deprecated and should be updated to use Connect-MgGraph:~~

**Legacy MSGraph Module (Deprecated):**
```powershell
# OLD METHOD - DO NOT USE
Update-MSGraphEnvironment -AppId {your app id}
$adminUPN = Read-Host -Prompt "Enter UPN"  
$adminPwd = Read-Host -AsSecureString -Prompt "Enter password for $adminUPN"
$credential = New-Object System.Management.Automation.PsCredential($adminUPN, $adminPwd)
Connect-MSGraph -PSCredential $credential
```

**Legacy MSAL Method (Deprecated):**
```powershell
# OLD METHOD - DO NOT USE
[System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
[System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
$clientId = "<replace with your clientID>"
$redirectUri = "urn:ietf:wg:oauth:2.0:oob"
$resourceAppIdURI = "https://graph.microsoft.com"
```

**Migration Path:**
Replace all legacy authentication methods with the modern `Connect-MgGraph` examples shown above. The Microsoft.Graph.Authentication module provides better security, multi-cloud support, and is actively maintained.
