---
page_type: sample
products:
- ms-graph
languages:
- powershell
extensions:
  contentType: samples
  technologies:
  - Microsoft Graph
  services:
  - Intune
  createdDate: 4/4/2017 9:41:27 AM
noDependencies: true
---
# IMPORTANT

Last year we announced a new Microsoft Intune GitHub repository [here](https://aka.ms/Intune/Scripts-blog) based on the Microsoft Graph SDK-based PowerShell module. This legacy Microsoft Intune PowerShell sample scripts GitHub repository is now read-only. Additionally, starting on April 1, 2024, due to updated authentication methods in the Graph SDK-based PowerShell module, the global Microsoft Intune PowerShell application (client) ID based authentication method is being removed.

### How this will affect your organization

If you are using the Intune PowerShell application ID (d1ddf0e4-d672-4dae-b554-9d5bdfd93547), you will need to update your scripts with a Microsoft Entra ID registered application ID to prevent your scripts from breaking.

### What you need to do to prepare

Before May 6, 2024, update your PowerShell scripts by:

1) Creating a new app registration in the Microsoft Entra admin center. For detailed instructions, read: [Quickstart: Register an application with the Microsoft identity platform](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app).
2) Update scripts containing the Intune application ID (d1ddf0e4-d672-4dae-b554-9d5bdfd93547) with the new application ID created in step 1.

Review the "Updating App Registration" file for detailed instructions. (https://github.com/microsoftgraph/powershell-intune-samples/blob/master/Updating%20App%20Registration)

# Intune Graph Samples

This repository of PowerShell sample scripts show how to access Intune service resources.  They demonstrate this by making HTTPS RESTful API requests to the Microsoft Graph API from PowerShell.

Documentation for Intune and Microsoft Graph can be found here [Intune Graph Documentation](https://docs.microsoft.com/en-us/graph/api/resources/intune-graph-overview?view=graph-rest-1.0).

These samples demonstrate typical Intune administrator or Microsoft partner actions for managing Intune resources.

The following samples are included in this repository:
- AdminConsent
- AndroidEnterprise
- AppleEnrollment
- Applications
- ApplicationSync
- AppProtectionPolicy
- Auditing
- Authentication
- CertificationAuthority
- CheckStatus
- CompanyPortalBranding
- CompliancePolicy
- CorporateDeviceEnrollment
- DeviceConfiguration
- EnrollmentRestrictions
- IntuneDataExport
- LOB_Application
- ManagedDevices
- Paging
- RBAC
- RemoteActionAudit
- SoftwareUpdates
- TermsAndConditions
- UserPolicyReport

The scripts are licensed "as-is." under the MIT License.

#### Disclaimer
Some script samples retrieve information from your Intune tenant, and others create, delete or update data in your Intune tenant.  Understand the impact of each sample script prior to running it; samples should be run using a non-production or "test" tenant account.

## Using the Intune Graph API
The Intune Graph API enables access to Intune information programmatically for your tenant, and the API performs the same Intune operations as those available through the Azure Portal.

Intune provides data into the Microsoft Graph in the same way as other cloud services do, with rich entity information and relationship navigation.  Use Microsoft Graph to combine information from other services and Intune to build rich cross-service applications for IT professionals or end users.

## Prerequisites
Use of these Microsoft Graph API Intune PowerShell samples requires the following:
* **Install the Microsoft.Graph.Authentication PowerShell module** by running `Install-Module Microsoft.Graph.Authentication` from an elevated PowerShell prompt
* **Legacy Support**: AzureAD PowerShell module support is deprecated (Install-Module AzureAD or AzureADPreview)
* An Intune tenant which supports the Azure Portal with a production or trial license (https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/what-is-intune)
* Using the Microsoft Graph APIs to configure Intune controls and policies requires an Intune license.
* An account with permissions to administer the Intune Service
* PowerShell v5.0 or 7.x on Windows 11 x64 supported
* First time usage of these scripts requires a Global Administrator of the Tenant to accept the permissions of the application

## Getting Started
After the prerequisites are installed or met, perform the following steps to use these scripts:

#### 1. Script usage

1. Download the contents of the repository to your local Windows machine
* Extract the files to a local folder (e.g. C:\IntuneGraphSamples)
* Run PowerShell x64 from the start menu
* Browse to the directory (e.g. cd C:\IntuneGraphSamples)
* **Install Microsoft Graph Authentication module**: `Install-Module Microsoft.Graph.Authentication`
* For each Folder in the local repository you can browse to that directory and then run the script of your choice
* Example Application script usage:
  * To use the Manage Applications scripts, from C:\IntuneGraphSamples, run "cd .\Applications\"
  * Once in the folder run .\Application_MDM_Get.ps1 to get all MDM added applications
  * **New**: Scripts automatically connect using `Connect-GraphAPI` with appropriate scopes
  * **Multi-Cloud**: Use `-Environment` parameter for different Microsoft clouds
  This sequence of steps can be used for each folder....

#### 2. Authentication with Microsoft Graph
**Graph Authentication (Recommended):**
The scripts now use the modern `Microsoft.Graph.Authentication` module. When you run any script, it will automatically:
1. Call `Connect-GraphAPI` with the appropriate scopes for that script
2. Prompt you to sign in through a web browser (more secure)
3. Cache the authentication token for the PowerShell session

```powershell
# Examples of modern authentication
Connect-GraphAPI                          # Global cloud with default scopes
Connect-GraphAPI -Environment "USGov"     # US Government cloud
Connect-GraphAPI -Environment "Germany"   # Germany cloud
```

**Legacy Authentication (Deprecated):**
The first time you run legacy scripts you will be asked to provide an account to authenticate with the service:
```
Please specify your user principal name for Azure Authentication:
```
Once you have provided a user principal name a popup will open prompting for your password. After a successful authentication with Azure Active Directory the user token will last for an hour, once the hour expires within the PowerShell session you will be asked to re-authenticate.

**Permission Consent:**
If you are running the script for the first time against your tenant a popup will be presented stating:

```
Microsoft Intune PowerShell needs permission to:

* Sign you in and read your profile
* Read all groups
* Read directory data
* Read and write Microsoft Intune Device Configuration and Policies (preview)
* Read and write Microsoft Intune RBAC settings (preview)
* Perform user-impacting remote actions on Microsoft Intune devices (preview)
* Sign in as you
* Read and write Microsoft Intune devices (preview)
* Read and write all groups
* Read and write Microsoft Intune configuration (preview)
* Read and write Microsoft Intune apps (preview)
```

Note: If your user account is targeted for device based conditional access your device must be enrolled or compliant to pass authentication.

## Recent Updates (August 2025)

This repository has been modernized to use the latest Microsoft Graph PowerShell authentication methods and best practices. The following updates have been implemented:

### 🔧 **Microsoft.Graph.Authentication Module**
- **Updated Authentication**: All scripts now use `Microsoft.Graph.Authentication` module instead of legacy authentication methods
- **Environment Support**: Added support for all Microsoft Cloud environments:
  - **Global**: `https://graph.microsoft.com` (default)
  - **US Government**: `https://graph.microsoft.us`
  - **US Government DoD**: `https://dod-graph.microsoft.us`
  - **China**: `https://microsoftgraph.chinacloudapi.cn`
  - **Germany**: `https://graph.microsoft.de`

### 🌐 **Multi-Cloud Environment Support**
- **Dynamic Endpoint Management**: Scripts automatically use the correct Graph endpoint based on your environment
- **Global Variables**: Added `$global:GraphEndpoint` variable for environment-aware operations
- **Flexible Authentication**: Use `-Environment` parameter to connect to different clouds:
  ```powershell
  Connect-GraphAPI -Environment "USGov"    # US Government
  Connect-GraphAPI -Environment "Germany"  # Germany Cloud
  ```
- **Removed Legacy Functions**: Eliminated old `Get-AuthToken` functions in favor of graph authentication

### 📡 **Graph REST API Function**
- **New `Invoke-IntuneRestMethod` Function**:
  - Replaced `Invoke-RestMethod` with `Authtoken`
  - Automatic paging support for large result sets
  - Environment-aware URI handling (relative and absolute paths)
  - Smart body parameter detection (JSON strings, plain strings, objects)
  - Built-in error handling and verbose logging

### 🔍 **Intelligent Parameter Handling**
- **Type-Agnostic Body Parameters**: Automatically detects and handles:
  - Valid JSON strings (used as-is)
  - Plain text strings (properly quoted)
  - PowerShell objects (converted to JSON)
- **Automatic URI Conversion**: Seamlessly handles both relative and absolute URIs

### 🛠 **Code Quality Improvements**
- **Trailing Whitespace Cleanup**: Removed trailing whitespace from 4,593 lines across 133 files
- **Character Encoding Fixes**: Fixed 96 en-dash characters (–) replaced with proper hyphens (-)
- **Consistent Formatting**: Standardized code formatting across all scripts

### 📋 **Scope Management**
- **Automatic Scope Detection**: Scripts automatically determine required permissions based on operation type:
  - **Read Operations**: Read-only scopes (`DeviceManagementConfiguration.Read.All`)
  - **Write Operations**: ReadWrite scopes (`DeviceManagementConfiguration.ReadWrite.All`)
  - **Context-Aware**: Different scopes for different resource types (Apps, Devices, Policies, etc.)

### 🔄 **Backward Compatibility**
- **Seamless Migration**: Existing script functionality remains the same
- **Updated Examples**: All code examples updated to use graph authentication module

### 🚀 **Getting Started with Modern Scripts**
1. **Install Required Module**:
   ```powershell
   Install-Module Microsoft.Graph.Authentication
   ```

2. **Connect to Microsoft Graph**:
   ```powershell
   Connect-GraphAPI                          # Global cloud (default)
   Connect-GraphAPI -Environment "USGov"     # US Government cloud
   ```

3. **Run Any Script**: All scripts now use the graph authentication automatically

## Contributing

If you'd like to contribute to this sample, see CONTRIBUTING.MD.

This project has adopted the Microsoft Open Source Code of Conduct. For more information see the Code of Conduct FAQ or contact opencode@microsoft.com with any additional questions or comments.

## Questions and comments

We'd love to get your feedback about the Intune PowerShell sample. You can send your questions and suggestions to us in the Issues section of this repository.

Your feedback is important to us. Connect with us on Stack Overflow. Tag your questions with [MicrosoftGraph] and [intune].


## Additional resources
* [Microsoft Graph API documentation](https://developer.microsoft.com/en-us/graph/docs)
* [Microsoft Graph Portal](https://developer.microsoft.com/en-us/graph/graph-explorer)
* [Microsoft code samples](https://developer.microsoft.com/en-us/graph/code-samples-and-sdks)
* [Intune Graph Documentation](https://docs.microsoft.com/en-us/graph/api/resources/intune-graph-overview?view=graph-rest-1.0)

## Copyright
Copyright (c) 2025 Microsoft. All rights reserved.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
