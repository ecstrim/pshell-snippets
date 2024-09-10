# Install the necessary modules if not already installed
# Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Force -SkipPublisherCheck
# Install-Module -Name SharePointPnPPowerShellOnline -Force

# Variables
$tenantUrl = "https://yourtenantname.sharepoint.com"
$siteUrl = "https://yourtenantname.sharepoint.com/sites/yoursite"
$libraryName = "Documents"
$folderName = "NewFolder"
$userToShare = "user@example.com"
$permissionLevel = "Edit"  # Can be View, Edit, etc.

# Connect to SharePoint Online
Connect-SPOService -Url $tenantUrl
$cred = Get-Credential
Connect-PnPOnline -Url $siteUrl -Credentials $cred

# Create a new folder
New-PnPFolder -Name $folderName -Folder "/$libraryName"

# Get the folder
$folder = Get-PnPFolder -Url "/$libraryName/$folderName"

# Share the folder
Set-PnPFolderPermission -List $libraryName -Identity $folder.Name -User $userToShare -AddRole $permissionLevel

Write-Host "Folder '$folderName' created and shared with '$userToShare' with '$permissionLevel' permission."
