
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

function CloneObject($object){

	$stream = New-Object IO.MemoryStream;
	$formatter = New-Object Runtime.Serialization.Formatters.Binary.BinaryFormatter;
	$formatter.Serialize($stream, $object);
	$stream.Position = 0;
	$formatter.Deserialize($stream);
}

####################################################

function WriteHeaders($authToken){

	foreach ($header in $authToken.GetEnumerator())
	{
		if ($header.Name.ToLower() -eq "authorization")
		{
			continue;
		}

		Write-Host -ForegroundColor Gray "$($header.Name): $($header.Value)";
	}
}

####################################################

function MakeGetRequest($collectionPath){

	$uri = "$baseUrl$collectionPath";
	$request = "GET $uri";

	if ($logRequestUris) { Write-Host $request; }
	if ($logHeaders) { WriteHeaders $authToken; }

	try
	{
		$response = Invoke-RestMethod $uri -Method Get -Headers $authToken;
		$response;
	}
	catch
	{
		Write-Host -ForegroundColor Red $request;
		Write-Host -ForegroundColor Red $_.Exception.Message;
		throw;
	}
}

####################################################

function MakePatchRequest($collectionPath, $body){

	MakeRequest "PATCH" $collectionPath $body;

}

####################################################

function MakePostRequest($collectionPath, $body){

	MakeRequest "POST" $collectionPath $body;

}

####################################################

function MakeRequest($verb, $collectionPath, $body){

	$uri = "$baseUrl$collectionPath";
	$request = "$verb $uri";

	$clonedHeaders = CloneObject $authToken;
	$clonedHeaders["content-length"] = $body.Length;
	$clonedHeaders["content-type"] = "application/json";

	if ($logRequestUris) { Write-Host $request; }
	if ($logHeaders) { WriteHeaders $clonedHeaders; }
	if ($logContent) { Write-Host -ForegroundColor Gray $body; }

	try
	{
		$response = Invoke-RestMethod $uri -Method $verb -Headers $clonedHeaders -Body $body;
		$response;
	}
	catch
	{
		Write-Host -ForegroundColor Red $request;
		Write-Host -ForegroundColor Red $_.Exception.Message;
		throw;
	}
}

####################################################

function UploadAzureStorageChunk($sasUri, $id, $body){

	$uri = "$sasUri&comp=block&blockid=$id";
	$request = "PUT $uri";

	$iso = [System.Text.Encoding]::GetEncoding("iso-8859-1");
	$encodedBody = $iso.GetString($body);
	$headers = @{
		"x-ms-blob-type" = "BlockBlob"
	};

	if ($logRequestUris) { Write-Host $request; }
	if ($logHeaders) { WriteHeaders $headers; }

	try
	{
		$response = Invoke-WebRequest $uri -Method Put -Headers $headers -Body $encodedBody;
	}
	catch
	{
		Write-Host -ForegroundColor Red $request;
		Write-Host -ForegroundColor Red $_.Exception.Message;
		throw;
	}

}

####################################################

function FinalizeAzureStorageUpload($sasUri, $ids){

	$uri = "$sasUri&comp=blocklist";
	$request = "PUT $uri";

	$xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>';
	foreach ($id in $ids)
	{
		$xml += "<Latest>$id</Latest>";
	}
	$xml += '</BlockList>';

	if ($logRequestUris) { Write-Host $request; }
	if ($logContent) { Write-Host -ForegroundColor Gray $xml; }

	try
	{
		Invoke-RestMethod $uri -Method Put -Body $xml;
	}
	catch
	{
		Write-Host -ForegroundColor Red $request;
		Write-Host -ForegroundColor Red $_.Exception.Message;
		throw;
	}
}

####################################################

function UploadFileToAzureStorage($sasUri, $filepath){

	# Chunk size = 1 MiB
    $chunkSizeInBytes = 1024 * 1024;

	# Read the whole file and find the total chunks.
	#[byte[]]$bytes = Get-Content $filepath -Encoding byte;
    # Using ReadAllBytes method as the Get-Content used alot of memory on the machine
    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($filepath);
	$chunks = [Math]::Ceiling($bytes.Length / $chunkSizeInBytes);

	# Upload each chunk.
	$ids = @();
    $cc = 1

	for ($chunk = 0; $chunk -lt $chunks; $chunk++)
	{
        $id = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($chunk.ToString("0000")));
		$ids += $id;

		$start = $chunk * $chunkSizeInBytes;
		$end = [Math]::Min($start + $chunkSizeInBytes - 1, $bytes.Length - 1);
		$body = $bytes[$start..$end];

        Write-Progress -Activity "Uploading File to Azure Storage" -status "Uploading chunk $cc of $chunks" `
        -percentComplete ($cc / $chunks*100)
        $cc++

        $uploadResponse = UploadAzureStorageChunk $sasUri $id $body;


	}

    Write-Progress -Completed -Activity "Uploading File to Azure Storage"

    Write-Host

	# Finalize the upload.
	$uploadResponse = FinalizeAzureStorageUpload $sasUri $ids;
}

####################################################

function GenerateKey{

	try
	{
		$aes = [System.Security.Cryptography.Aes]::Create();
        $aesProvider = New-Object System.Security.Cryptography.AesCryptoServiceProvider;
        $aesProvider.GenerateKey();
        $aesProvider.Key;
	}
	finally
	{
		if ($null -ne $aesProvider) { $aesProvider.Dispose(); }
		if ($null -ne $aes) { $aes.Dispose(); }
	}
}

####################################################

function GenerateIV{

	try
	{
		$aes = [System.Security.Cryptography.Aes]::Create();
        $aes.IV;
	}
	finally
	{
		if ($null -ne $aes) { $aes.Dispose(); }
	}
}

####################################################

function EncryptFileWithIV($sourceFile, $targetFile, $encryptionKey, $hmacKey, $initializationVector){

	$bufferBlockSize = 1024 * 4;
	$computedMac = $null;

	try
	{
		$aes = [System.Security.Cryptography.Aes]::Create();
		$hmacSha256 = New-Object System.Security.Cryptography.HMACSHA256;
		$hmacSha256.Key = $hmacKey;
		$hmacLength = $hmacSha256.HashSize / 8;

		$buffer = New-Object byte[] $bufferBlockSize;
		$bytesRead = 0;

		$targetStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read);
		$targetStream.Write($buffer, 0, $hmacLength + $initializationVector.Length);

		try
		{
			$encryptor = $aes.CreateEncryptor($encryptionKey, $initializationVector);
			$sourceStream = [System.IO.File]::Open($sourceFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read);
			$cryptoStream = New-Object System.Security.Cryptography.CryptoStream -ArgumentList @($targetStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write);

			$targetStream = $null;
			while (($bytesRead = $sourceStream.Read($buffer, 0, $bufferBlockSize)) -gt 0)
			{
				$cryptoStream.Write($buffer, 0, $bytesRead);
				$cryptoStream.Flush();
			}
			$cryptoStream.FlushFinalBlock();
		}
		finally
		{
			if ($null -ne $cryptoStream) { $cryptoStream.Dispose(); }
			if ($null -ne $sourceStream) { $sourceStream.Dispose(); }
			if ($null -ne $encryptor) { $encryptor.Dispose(); }
		}

		try
		{
			$finalStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)

			$finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) > $null;
			$finalStream.Write($initializationVector, 0, $initializationVector.Length);
			$finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) > $null;

			$hmac = $hmacSha256.ComputeHash($finalStream);
			$computedMac = $hmac;

			$finalStream.Seek(0, [System.IO.SeekOrigin]::Begin) > $null;
			$finalStream.Write($hmac, 0, $hmac.Length);
		}
		finally
		{
			if ($null -ne $finalStream) { $finalStream.Dispose(); }
		}
	}
	finally
	{
		if ($null -ne $targetStream) { $targetStream.Dispose(); }
        if ($null -ne $aes) { $aes.Dispose(); }
	}

	$computedMac;
}

####################################################

function EncryptFile($sourceFile, $targetFile){

	$encryptionKey = GenerateKey;
	$hmacKey = GenerateKey;
	$initializationVector = GenerateIV;

	# Create the encrypted target file and compute the HMAC value.
	$mac = EncryptFileWithIV $sourceFile $targetFile $encryptionKey $hmacKey $initializationVector;

	# Compute the SHA256 hash of the source file and convert the result to bytes.
	$fileDigest = (Get-FileHash $sourceFile -Algorithm SHA256).Hash;
	$fileDigestBytes = New-Object byte[] ($fileDigest.Length / 2);
    for ($i = 0; $i -lt $fileDigest.Length; $i += 2)
	{
        $fileDigestBytes[$i / 2] = [System.Convert]::ToByte($fileDigest.Substring($i, 2), 16);
    }

	# Return an object that will serialize correctly to the file commit Graph API.
	$encryptionInfo = @{};
	$encryptionInfo.encryptionKey = [System.Convert]::ToBase64String($encryptionKey);
	$encryptionInfo.macKey = [System.Convert]::ToBase64String($hmacKey);
	$encryptionInfo.initializationVector = [System.Convert]::ToBase64String($initializationVector);
	$encryptionInfo.mac = [System.Convert]::ToBase64String($mac);
	$encryptionInfo.profileIdentifier = "ProfileVersion1";
	$encryptionInfo.fileDigest = [System.Convert]::ToBase64String($fileDigestBytes);
	$encryptionInfo.fileDigestAlgorithm = "SHA256";

	$fileEncryptionInfo = @{};
	$fileEncryptionInfo.fileEncryptionInfo = $encryptionInfo;

	$fileEncryptionInfo;

}

####################################################

function WaitForFileProcessing($fileUri, $stage){

	$attempts= 60;
	$waitTimeInSeconds = 1;

	$successState = "$($stage)Success";
	$pendingState = "$($stage)Pending";
	$failedState = "$($stage)Failed";
	$timedOutState = "$($stage)TimedOut";

	$file = $null;
	while ($attempts -gt 0)
	{
		$file = MakeGetRequest $fileUri;

		if ($file.uploadState -eq $successState)
		{
			break;
		}
		elseif ($file.uploadState -ne $pendingState)
		{
			throw "File upload state is not success: $($file.uploadState)";
		}

		Start-Sleep $waitTimeInSeconds;
		$attempts--;
	}

	if ($null -eq $file)
	{
		throw "File request did not complete in the allotted time.";
	}

	$file;

}

####################################################

function GetAndroidAppBody($displayName, $publisher, $description, $filename, $identityName, $identityVersion, $versionName, $minimumSupportedOperatingSystem){

	$body = @{ "@odata.type" = "#microsoft.graph.androidLOBApp" };
	$body.categories = @();
	$body.displayName = $displayName;
	$body.publisher = $publisher;
	$body.description = $description;
	$body.fileName = $filename;
	$body.identityName = $identityName;
	$body.identityVersion = $identityVersion;

    if ($null -eq $minimumSupportedOperatingSystem){

		$body.minimumSupportedOperatingSystem = @{ "v4_4" = $true };

    }

    else {

		$body.minimumSupportedOperatingSystem = $minimumSupportedOperatingSystem;

    }

	$body.informationUrl = $null;
	$body.isFeatured = $false;
	$body.privacyInformationUrl = $null;
	$body.developer = "";
	$body.notes = "";
	$body.owner = "";
    $body.versionCode = $identityVersion;
    $body.versionName = $versionName;

	$body;
}

####################################################

function GetiOSAppBody($displayName, $publisher, $description, $filename, $bundleId, $identityVersion, $versionNumber, $expirationDateTime){

	$body = @{ "@odata.type" = "#microsoft.graph.iosLOBApp" };
    $body.applicableDeviceType = @{ "iPad" = $true; "iPhoneAndIPod" = $true }
	$body.categories = @();
	$body.displayName = $displayName;
	$body.publisher = $publisher;
	$body.description = $description;
	$body.fileName = $filename;
	$body.bundleId = $bundleId;
	$body.identityVersion = $identityVersion;
	if ($null -eq $minimumSupportedOperatingSystem)
	{
		$body.minimumSupportedOperatingSystem = @{ "v9_0" = $true };
	}
	else
	{
		$body.minimumSupportedOperatingSystem = $minimumSupportedOperatingSystem;
	}

	$body.informationUrl = $null;
	$body.isFeatured = $false;
	$body.privacyInformationUrl = $null;
	$body.developer = "";
	$body.notes = "";
	$body.owner = "";
    $body.expirationDateTime = $expirationDateTime;
    $body.versionNumber = $versionNumber;

	$body;
}

####################################################

function GetMSIAppBody($displayName, $publisher, $description, $filename, $identityVersion, $ProductCode){

	$body = @{ "@odata.type" = "#microsoft.graph.windowsMobileMSI" };
	$body.displayName = $displayName;
	$body.publisher = $publisher;
	$body.description = $description;
	$body.fileName = $filename;
	$body.identityVersion = $identityVersion;
	$body.informationUrl = $null;
	$body.isFeatured = $false;
	$body.privacyInformationUrl = $null;
	$body.developer = "";
	$body.notes = "";
	$body.owner = "";
    $body.productCode = "$ProductCode";
    $body.productVersion = "$identityVersion";

	$body;
}

####################################################

function GetAppFileBody($name, $size, $sizeEncrypted, $manifest){

	$body = @{ "@odata.type" = "#microsoft.graph.mobileAppContentFile" };
	$body.name = $name;
	$body.size = $size;
	$body.sizeEncrypted = $sizeEncrypted;
	$body.manifest = $manifest;

	$body;
}

####################################################

function GetAppCommitBody($contentVersionId, $LobType){

	$body = @{ "@odata.type" = "#$LobType" };
	$body.committedContentVersion = $contentVersionId;

	$body;

}

####################################################

function Get-MSIFileInformation {

# https://www.scconfigmgr.com/2014/08/22/how-to-get-msi-file-information-with-powershell/

param(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [System.IO.FileInfo]$Path,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("ProductCode", "ProductVersion", "ProductName", "Manufacturer", "ProductLanguage", "FullVersion")]
    [string]$Property
)
Process {

    try {
        # Read property from MSI database
        $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $MSIDatabase = $WindowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $WindowsInstaller, @($Path.FullName, 0))
        $Query = "SELECT Value FROM Property WHERE Property = '$($Property)'"
        $View = $MSIDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $MSIDatabase, ($Query))
        $View.GetType().InvokeMember("Execute", "InvokeMethod", $null, $View, $null)
        $Record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $View, $null)
        $Value = $Record.GetType().InvokeMember("StringData", "GetProperty", $null, $Record, 1)

        # Commit database and close view
        $MSIDatabase.GetType().InvokeMember("Commit", "InvokeMethod", $null, $MSIDatabase, $null)
        $View.GetType().InvokeMember("Close", "InvokeMethod", $null, $View, $null)
        $MSIDatabase = $null
        $View = $null

        # Return the value
        return $Value
    }

    catch {

        Write-Warning -Message $_.Exception.Message;
        break;

    }

}

    End {
        # Run garbage collection and release ComObject
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WindowsInstaller) | Out-Null
        [System.GC]::Collect()
    }

}

####################################################

function Test-SourceFile {

param
(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $SourceFile
)

    try {

            if(!(test-path "$SourceFile")){

            Write-Host "Source File '$sourceFile' doesn't exist..." -ForegroundColor Red
            throw

            }

        }

    catch {

		Write-Host -ForegroundColor Red $_.Exception.Message;
        Write-Host
		break;

    }

}

####################################################

Function Get-ApkInformation {

<#
.SYNOPSIS
This function is used to get information about an Android APK file using the Android SDK - https://developer.android.com/studio/index.html
.DESCRIPTION
This function is used to get information about an Android APK file using the Android SDK - https://developer.android.com/studio/index.html
.EXAMPLE
Get-ApkInformation -sourceFile c:\source\application.apk
Function will return two object, object[0] is the identityName and object[1] is the identityVersion
.NOTES
NAME: Get-ApkInformation
#>

[cmdletbinding()]

param
(
    [Parameter(Mandatory=$true)]
    $sourceFile,
    [Parameter(Mandatory=$true)]
    $AndroidSDK
)

    if(!(test-path $AndroidSDK)){

    Write-Host
    Write-Host "Android SDK isn't installed..." -ForegroundColor Red
    Write-Host "Please install Android Studio and install the SDK from https://developer.android.com/studio/index.html"
    Write-Host
    break

    }

    if(((gci $AndroidSDK | select name).Name).count -gt 1){

    $BuildTools = ((gci $AndroidSDK | select name).Name | sort -Descending)[0]

    }

    else {

    $BuildTools = ((gci $AndroidSDK | select name).Name)

    }

$aaptPath = "$AndroidSDK\$BuildTools"

[ScriptBlock]$command = {

    cmd.exe /c "$aaptPath\aapt.exe" dump badging "$sourceFile"

}

$aaptRun = Invoke-Command -ScriptBlock $command

$AndroidPackage = $aaptRun | ? { ($_).startswith("package") }

$PackageInfo = $AndroidPackage.split(" ")

$PackageInfo[1].Split("'")[1]
$PackageInfo[2].Split("'")[1]
$PackageInfo[3].Split("'")[1]

if ($logContent) { Write-Host -ForegroundColor Gray $PackageInfo[1].Split("'")[1]; }
if ($logContent) { Write-Host -ForegroundColor Gray $PackageInfo[2].Split("'")[1]; }
if ($logContent) { Write-Host -ForegroundColor Gray $PackageInfo[3].Split("'")[1]; }

}

####################################################

function Upload-AndroidLob {

<#
.SYNOPSIS
This function is used to upload an Android LOB Application to the Intune Service
.DESCRIPTION
This function is used to upload an Android LOB Application to the Intune Service
.EXAMPLE
Upload-AndroidLob -sourceFile "C:\Software\package.apk" -publisher "Publisher Name" -description "Description of Application" -identityName "com.package" -identityVersion "1" -versionName "10.1.1"
This example uses all parameters required to add an Android Application into the Intune Service
Upload-AndroidLob -sourceFile "C:\Software\package.apk" -publisher "Publisher Name" -description "Description of Application"
This example uses the required parameters to add an Android Application into the Intune Service. This example will require the Android SDK to get identityName and identityVersion
.NOTES
NAME: Upload-AndroidLOB
#>

[cmdletbinding()]

param
(
    [parameter(Mandatory=$true,Position=1)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceFile,

    [parameter(Mandatory=$false)]
    [string]$displayName,

    [parameter(Mandatory=$true,Position=2)]
    [ValidateNotNullOrEmpty()]
    [string]$publisher,

    [parameter(Mandatory=$true,Position=3)]
    [ValidateNotNullOrEmpty()]
    [string]$description,

    [parameter(Mandatory=$false)]
    [string]$identityName,

    [parameter(Mandatory=$false)]
    [string]$identityVersion,

    [parameter(Mandatory=$false)]
    [string]$versionName

)

	try
	{

        $LOBType = "microsoft.graph.androidLOBApp"

        Write-Host "Testing if SourceFile '$SourceFile' Path is valid..." -ForegroundColor Yellow
        Test-SourceFile "$SourceFile"

            if(!$identityName){

            Write-Host
            Write-Host "Opening APK file to get identityName to pass to the service..." -ForegroundColor Yellow

            $APKInformation = Get-ApkInformation -AndroidSDK $AndroidSDKLocation -sourceFile "$SourceFile"

            $identityName = $APKInformation[0]

            }

            if(!$identityVersion){

            Write-Host
            Write-Host "Opening APK file to get identityVersion to pass to the service..." -ForegroundColor Yellow

            $APKInformation = Get-ApkInformation -AndroidSDK $AndroidSDKLocation -sourceFile "$SourceFile"

            $identityVersion = $APKInformation[1]

            }

            if(!$versionName){

            Write-Host
            Write-Host "Opening APK file to get versionName to pass to the service..." -ForegroundColor Yellow

            $APKInformation = Get-ApkInformation -AndroidSDK $AndroidSDKLocation -sourceFile "$SourceFile"

            $versionName = $APKInformation[2]

            }


        # Creating temp file name from Source File path
        $tempFile = [System.IO.Path]::GetDirectoryName("$SourceFile") + "\" + [System.IO.Path]::GetFileNameWithoutExtension("$SourceFile") + "_temp.bin"

        # Creating filename variable from Source File Path
        $filename = [System.IO.Path]::GetFileName("$SourceFile")

            if(!($displayName)){

            $displayName = $filename

            }

        # Create a new Android LOB app.
        Write-Host
        Write-Host "Creating JSON data to pass to the service..." -ForegroundColor Yellow
		$mobileAppBody = GetAndroidAppBody "$displayName" "$Publisher" "$Description" "$filename" "$identityName" "$identityVersion" "$versionName";

        Write-Host
        Write-Host "Creating application in Intune..." -ForegroundColor Yellow
        $mobileApp = MakePostRequest "mobileApps" ($mobileAppBody | ConvertTo-Json);

		# Get the content version for the new app (this will always be 1 until the new app is committed).
        Write-Host
        Write-Host "Creating Content Version in the service for the application..." -ForegroundColor Yellow
		$appId = $mobileApp.id;
		$contentVersionUri = "mobileApps/$appId/$LOBType/contentVersions";
		$contentVersion = MakePostRequest $contentVersionUri "{}";

        # Encrypt file and Get File Information
        Write-Host
        Write-Host "Ecrypting the file '$SourceFile'..." -ForegroundColor Yellow
        $encryptionInfo = EncryptFile "$sourceFile" "$tempFile";
        $Size = (Get-Item "$sourceFile").Length
        $EncrySize = (Get-Item "$tempFile").Length

        Write-Host
        Write-Host "Creating the manifest file used to install the application on the device..." -ForegroundColor Yellow

        [xml]$manifestXML = '<?xml version="1.0" encoding="utf-8"?><AndroidManifestProperties xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Package>com.leadapps.android.radio.ncp</Package><PackageVersionCode>10</PackageVersionCode><PackageVersionName>1.0.5.4</PackageVersionName><ApplicationName>A_Online_Radio_1.0.5.4.apk</ApplicationName><MinSdkVersion>3</MinSdkVersion><AWTVersion></AWTVersion></AndroidManifestProperties>'

        $manifestXML.AndroidManifestProperties.Package = "$identityName" # com.application.test
        $manifestXML.AndroidManifestProperties.PackageVersionCode = "$identityVersion" # 10
        $manifestXML.AndroidManifestProperties.PackageVersionName = "$identityVersion" # 1.0.5.4
        $manifestXML.AndroidManifestProperties.ApplicationName = "$filename" # name.apk

        $manifestXML_Output = $manifestXML.OuterXml.ToString()

        $Bytes = [System.Text.Encoding]::ASCII.GetBytes($manifestXML_Output)
        $EncodedText =[Convert]::ToBase64String($Bytes)

		# Create a new file for the app.
        Write-Host
        Write-Host "Creating a new file entry in Azure for the upload..." -ForegroundColor Yellow
		$contentVersionId = $contentVersion.id;
		$fileBody = GetAppFileBody "$filename" $Size $EncrySize "$EncodedText";
		$filesUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files";
		$file = MakePostRequest $filesUri ($fileBody | ConvertTo-Json);

		# Wait for the service to process the new file request.
        Write-Host
        Write-Host "Waiting for the file entry URI to be created..." -ForegroundColor Yellow
		$fileId = $file.id;
		$fileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId";
		$file = WaitForFileProcessing $fileUri "AzureStorageUriRequest";

        # Upload the content to Azure Storage.
        Write-Host
        Write-Host "Uploading file to Azure Storage URI..." -ForegroundColor Yellow

        $sasUri = $file.azureStorageUri;
		UploadFileToAzureStorage $file.azureStorageUri $tempFile;

		# Commit the file.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
		$commitFileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId/commit";
		MakePostRequest $commitFileUri ($encryptionInfo | ConvertTo-Json);

		# Wait for the service to process the commit file request.
        Write-Host
        Write-Host "Waiting for the service to process the commit file request..." -ForegroundColor Yellow
		$file = WaitForFileProcessing $fileUri "CommitFile";

		# Commit the app.
        Write-Host
        Write-Host "Committing the application to the Intune Service..." -ForegroundColor Yellow
		$commitAppUri = "mobileApps/$appId";
		$commitAppBody = GetAppCommitBody $contentVersionId $LOBType;
		MakePatchRequest $commitAppUri ($commitAppBody | ConvertTo-Json);

        Write-Host "Removing Temporary file '$tempFile'..." -f Gray
        Remove-Item -Path "$tempFile" -Force
        Write-Host

        Write-Host "Sleeping for $sleep seconds to allow patch completion..." -f Magenta
        Start-Sleep $sleep
        Write-Host

	}
	catch
	{
		Write-Host "";
		Write-Host -ForegroundColor Red "Aborting with exception: $($_.Exception.ToString())";
	}
}

####################################################

function Upload-iOSLob {

<#
.SYNOPSIS
This function is used to upload an iOS LOB Application to the Intune Service
.DESCRIPTION
This function is used to upload an iOS LOB Application to the Intune Service
.EXAMPLE
Upload-iOSLob -sourceFile "C:\Software\package.ipa" -displayName "package.ipa" -publisher "Publisher Name" -description "Description of Application" -bundleId "com.package" -identityVersion "1" -versionNumber "3.0.0" -expirationDateTime "2018-02-14T20:53:52Z"
This example uses all parameters required to add an iOS Application into the Intune Service
.NOTES
NAME: Upload-iOSLOB
#>

[cmdletbinding()]

param
(
    [parameter(Mandatory=$true,Position=1)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceFile,

    [parameter(Mandatory=$true,Position=2)]
    [ValidateNotNullOrEmpty()]
    [string]$displayName,

    [parameter(Mandatory=$true,Position=3)]
    [ValidateNotNullOrEmpty()]
    [string]$publisher,

    [parameter(Mandatory=$true,Position=4)]
    [ValidateNotNullOrEmpty()]
    [string]$description,

    [parameter(Mandatory=$true,Position=5)]
    [ValidateNotNullOrEmpty()]
    [string]$bundleId,

    [parameter(Mandatory=$true,Position=6)]
    [ValidateNotNullOrEmpty()]
    [string]$identityVersion,

    [parameter(Mandatory=$true,Position=7)]
    [ValidateNotNullOrEmpty()]
    [string]$versionNumber,

    [parameter(Mandatory=$true,Position=8)]
    [ValidateNotNullOrEmpty()]
    [string]$expirationDateTime
)

	try
	{

        $LOBType = "microsoft.graph.iosLOBApp"

        Write-Host "Testing if SourceFile '$SourceFile' Path is valid..." -ForegroundColor Yellow
        Test-SourceFile "$SourceFile"

        # Checking expirationdatetime of SourceFile to check if it can be uploaded
        [datetimeoffset]$Expiration = $expirationDateTime

        $Date = get-date

            if($Expiration -lt $Date){

                Write-Error "$SourceFile has expired Follow the guidelines provided by Apple to extend the expiration date, then try adding the app again"
                throw

            }

        # Creating temp file name from Source File path
        $tempFile = [System.IO.Path]::GetDirectoryName("$SourceFile") + "\" + [System.IO.Path]::GetFileNameWithoutExtension("$SourceFile") + "_temp.bin"

        # Creating filename variable from Source File Path
        $filename = [System.IO.Path]::GetFileName("$SourceFile")

        # Create a new iOS LOB app.
        Write-Host
        Write-Host "Creating JSON data to pass to the service..." -ForegroundColor Yellow
		$mobileAppBody = GetiOSAppBody "$displayName" "$Publisher" "$Description" "$filename" "$bundleId" "$identityVersion" "$versionNumber" "$expirationDateTime";

        Write-Host
        Write-Host "Creating application in Intune..." -ForegroundColor Yellow

		$mobileApp = MakePostRequest "mobileApps" ($mobileAppBody | ConvertTo-Json);

		# Get the content version for the new app (this will always be 1 until the new app is committed).
        Write-Host
        Write-Host "Creating Content Version in the service for the application..." -ForegroundColor Yellow
		$appId = $mobileApp.id;
		$contentVersionUri = "mobileApps/$appId/$LOBType/contentVersions";
		$contentVersion = MakePostRequest $contentVersionUri "{}";

        # Encrypt file and Get File Information
        Write-Host
        Write-Host "Ecrypting the file '$SourceFile'..." -ForegroundColor Yellow
        $encryptionInfo = EncryptFile $sourceFile $tempFile;
        $Size = (Get-Item "$sourceFile").Length
        $EncrySize = (Get-Item "$tempFile").Length

        Write-Host
        Write-Host "Creating the manifest file used to install the application on the device..." -ForegroundColor Yellow

        [string]$manifestXML = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>items</key><array><dict><key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>{UrlPlaceHolder}</string></dict></array><key>metadata</key><dict><key>AppRestrictionPolicyTemplate</key> <string>http://management.microsoft.com/PolicyTemplates/AppRestrictions/iOS/v1</string><key>AppRestrictionTechnology</key><string>Windows Intune Application Restrictions Technology for iOS</string><key>IntuneMAMVersion</key><string></string><key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array><key>MinimumOSVersion</key><string>9.0</string><key>bundle-identifier</key><string>bundleid</string><key>bundle-version</key><string>bundleversion</string><key>kind</key><string>software</string><key>subtitle</key><string>LaunchMeSubtitle</string><key>title</key><string>bundletitle</string></dict></dict></array></dict></plist>'

        $manifestXML = $manifestXML.replace("bundleid","$bundleId")
        $manifestXML = $manifestXML.replace("bundleversion","$identityVersion")
        $manifestXML = $manifestXML.replace("bundletitle","$displayName")

        $Bytes = [System.Text.Encoding]::ASCII.GetBytes($manifestXML)
        $EncodedText =[Convert]::ToBase64String($Bytes)

		# Create a new file for the app.
        Write-Host
        Write-Host "Creating a new file entry in Azure for the upload..." -ForegroundColor Yellow
		$contentVersionId = $contentVersion.id;
		$fileBody = GetAppFileBody "$filename" $Size $EncrySize "$EncodedText";
		$filesUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files";
		$file = MakePostRequest $filesUri ($fileBody | ConvertTo-Json);

		# Wait for the service to process the new file request.
        Write-Host
        Write-Host "Waiting for the file entry URI to be created..." -ForegroundColor Yellow
		$fileId = $file.id;
		$fileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId";
		$file = WaitForFileProcessing $fileUri "AzureStorageUriRequest";

        # Upload the content to Azure Storage.
        Write-Host
        Write-Host "Uploading file to Azure Storage..." -f Yellow

		$sasUri = $file.azureStorageUri;
		UploadFileToAzureStorage $file.azureStorageUri $tempFile;

		# Commit the file.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
		$commitFileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId/commit";
		MakePostRequest $commitFileUri ($encryptionInfo | ConvertTo-Json);

		# Wait for the service to process the commit file request.
        Write-Host
        Write-Host "Waiting for the service to process the commit file request..." -ForegroundColor Yellow
		$file = WaitForFileProcessing $fileUri "CommitFile";

		# Commit the app.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
		$commitAppUri = "mobileApps/$appId";
		$commitAppBody = GetAppCommitBody $contentVersionId $LOBType;
		MakePatchRequest $commitAppUri ($commitAppBody | ConvertTo-Json);

        Write-Host "Removing Temporary file '$tempFile'..." -f Gray
        Remove-Item -Path "$tempFile" -Force
        Write-Host

        Write-Host "Sleeping for $sleep seconds to allow patch completion..." -f Magenta
        Start-Sleep $sleep
        Write-Host

	}
	catch
	{
		Write-Host "";
		Write-Host -ForegroundColor Red "Aborting with exception: $($_.Exception.ToString())";
	}
}

####################################################

function Upload-MSILob {

<#
.SYNOPSIS
This function is used to upload an MSI LOB Application to the Intune Service
.DESCRIPTION
This function is used to upload an MSI LOB Application to the Intune Service
.EXAMPLE
Upload-MSILob "C:\Software\Orca\Orca.Msi" -publisher "Microsoft" -description "Orca"
This example uses all parameters required to add an MSI Application into the Intune Service
.NOTES
NAME: Upload-MSILOB
#>

[cmdletbinding()]

param
(
    [parameter(Mandatory=$true,Position=1)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceFile,

    [parameter(Mandatory=$true,Position=2)]
    [ValidateNotNullOrEmpty()]
    [string]$publisher,

    [parameter(Mandatory=$true,Position=3)]
    [ValidateNotNullOrEmpty()]
    [string]$description
)

	try	{

        $LOBType = "microsoft.graph.windowsMobileMSI"

        Write-Host "Testing if SourceFile '$SourceFile' Path is valid..." -ForegroundColor Yellow
        Test-SourceFile "$SourceFile"

        $MSIPath = "$SourceFile"

        # Creating temp file name from Source File path
        $tempFile = [System.IO.Path]::GetDirectoryName("$SourceFile") + "\" + [System.IO.Path]::GetFileNameWithoutExtension("$SourceFile") + "_temp.bin"

        Write-Host
        Write-Host "Creating JSON data to pass to the service..." -ForegroundColor Yellow

        $FileName = [System.IO.Path]::GetFileName("$MSIPath")

        $PN = (Get-MSIFileInformation -Path "$MSIPath" -Property ProductName | Out-String).trimend()
        $PC = (Get-MSIFileInformation -Path "$MSIPath" -Property ProductCode | Out-String).trimend()
        $PV = (Get-MSIFileInformation -Path "$MSIPath" -Property ProductVersion | Out-String).trimend()
        $PL = (Get-MSIFileInformation -Path "$MSIPath" -Property ProductLanguage | Out-String).trimend()

		# Create a new MSI LOB app.
		$mobileAppBody = GetMSIAppBody -displayName "$PN" -publisher "$publisher" -description "$description" -filename "$FileName" -identityVersion "$PV" -ProductCode "$PC"

        Write-Host
        Write-Host "Creating application in Intune..." -ForegroundColor Yellow
		$mobileApp = MakePostRequest "mobileApps" ($mobileAppBody | ConvertTo-Json);

		# Get the content version for the new app (this will always be 1 until the new app is committed).
        Write-Host
        Write-Host "Creating Content Version in the service for the application..." -ForegroundColor Yellow
		$appId = $mobileApp.id;
		$contentVersionUri = "mobileApps/$appId/$LOBType/contentVersions";
		$contentVersion = MakePostRequest $contentVersionUri "{}";

        # Encrypt file and Get File Information
        Write-Host
        Write-Host "Ecrypting the file '$SourceFile'..." -ForegroundColor Yellow
        $encryptionInfo = EncryptFile $sourceFile $tempFile;
        $Size = (Get-Item "$sourceFile").Length
        $EncrySize = (Get-Item "$tempFile").Length

        Write-Host
        Write-Host "Creating the manifest file used to install the application on the device..." -ForegroundColor Yellow

        [xml]$manifestXML = '<MobileMsiData MsiExecutionContext="Any" MsiRequiresReboot="false" MsiUpgradeCode="" MsiIsMachineInstall="true" MsiIsUserInstall="false" MsiIncludesServices="false" MsiContainsSystemRegistryKeys="false" MsiContainsSystemFolders="false"></MobileMsiData>'

        $manifestXML.MobileMsiData.MsiUpgradeCode = "$PC"

        $manifestXML_Output = $manifestXML.OuterXml.ToString()

        $Bytes = [System.Text.Encoding]::ASCII.GetBytes($manifestXML_Output)
        $EncodedText =[Convert]::ToBase64String($Bytes)

		# Create a new file for the app.
        Write-Host
        Write-Host "Creating a new file entry in Azure for the upload..." -ForegroundColor Yellow
		$contentVersionId = $contentVersion.id;
		$fileBody = GetAppFileBody "$FileName" $Size $EncrySize "$EncodedText";
		$filesUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files";
		$file = MakePostRequest $filesUri ($fileBody | ConvertTo-Json);

		# Wait for the service to process the new file request.
        Write-Host
        Write-Host "Waiting for the file entry URI to be created..." -ForegroundColor Yellow
		$fileId = $file.id;
		$fileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId";
		$file = WaitForFileProcessing $fileUri "AzureStorageUriRequest";

		# Upload the content to Azure Storage.
        Write-Host
        Write-Host "Uploading file to Azure Storage..." -f Yellow

		$sasUri = $file.azureStorageUri;
		UploadFileToAzureStorage $file.azureStorageUri $tempFile;

		# Commit the file.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
		$commitFileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId/commit";
		MakePostRequest $commitFileUri ($encryptionInfo | ConvertTo-Json);

		# Wait for the service to process the commit file request.
        Write-Host
        Write-Host "Waiting for the service to process the commit file request..." -ForegroundColor Yellow
		$file = WaitForFileProcessing $fileUri "CommitFile";

		# Commit the app.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
		$commitAppUri = "mobileApps/$appId";
		$commitAppBody = GetAppCommitBody $contentVersionId $LOBType;
		MakePatchRequest $commitAppUri ($commitAppBody | ConvertTo-Json);

        Write-Host "Removing Temporary file '$tempFile'..." -f Gray
        Remove-Item -Path "$tempFile" -Force
        Write-Host

        Write-Host "Sleeping for $sleep seconds to allow patch completion..." -f Magenta
        Start-Sleep $sleep
        Write-Host

	}

    catch {

		Write-Host "";
		Write-Host -ForegroundColor Red "Aborting with exception: $($_.Exception.ToString())";

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

# Path to Android SDK Location to find aapt.exe tool if you don't specify identityName or identityVersion
# Note: Don't specify direct location to build folder number, just to the build-tools folder as the script will find the latest SDK installed
$AndroidSDKLocation = "C:\AndroidSDK\build-tools"

$baseUrl = "beta/deviceAppManagement/"

$logRequestUris = $true;
$logHeaders = $false;
$logContent = $true;

$sleep = 30

####################################################

#### Without Android SDK - All parameters are specified
# Upload-AndroidLob -sourceFile "C:\Software\OnlineRadio\A_Online_Radio_1.0.5.4.apk" -publisher "A Online Radio" -description "A Online Radio 1.0.5.4" -identityName "com.leadapps.android.radio.ncp" -identityVersion "10" -versionName "1.0.5.4"

#### With Android SDK:
# Upload-AndroidLob -sourceFile "C:\Software\OnlineRadio\A_Online_Radio_1.0.5.4.apk" -publisher "A Online Radio" -description "A Online Radio 1.0.5.4"

#### MSI
# Upload-MSILob "C:\Software\Orca\Orca.Msi" -publisher "Microsoft" -description "Orca"

#### iOS
# Upload-iOSLob -sourceFile "C:\Software\iOS\MyApp.ipa" -displayName "MyApp.ipa" -publisher "MyApp" -description "MyApp" -bundleId "com.microsoft.myApp" -identityVersion "1.0.0.0" -versionNumber "3.0.0" -expirationDateTime "2018-03-14T20:53:52Z"

