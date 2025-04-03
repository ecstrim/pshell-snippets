# Ensure the script is running with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as an Administrator!"
    exit 1
}

# Create a directory for logs and temporary files if it doesn't exist
$TempDir = "C:\Temp"
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force
}

# Start logging to a file
$LogFile = "$TempDir\AgentInstall.log"
Start-Transcript -Path $LogFile

# Function to download files
function Download-File {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )
    try {
        Write-Output "Downloading from $Url..."
        Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop
        Write-Output "Downloaded file to $Destination."
    }
    catch {
        Write-Error "Error downloading file from $Url. Exception: $_"
        Stop-Transcript
        exit 1
    }
}

# Example 1: Download and install Microsoft Monitoring Agent (MMA)
$MMAInstallerUrl = "https://example.com/path/to/MMAInstaller.msi"  # Replace with your actual URL
$MMAInstallerPath = "$TempDir\MMAInstaller.msi"

Download-File -Url $MMAInstallerUrl -Destination $MMAInstallerPath

try {
    Write-Output "Installing Microsoft Monitoring Agent..."
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$MMAInstallerPath`" /qn" -Wait -NoNewWindow
    Write-Output "Microsoft Monitoring Agent installation completed."
}
catch {
    Write-Error "Installation of Microsoft Monitoring Agent failed. Exception: $_"
    Stop-Transcript
    exit 1
}

# Example 2: Download and install a Custom Agent
$CustomAgentUrl = "https://example.com/path/to/CustomAgentInstaller.exe"  # Replace with your actual URL
$CustomAgentPath = "$TempDir\CustomAgentInstaller.exe"

Download-File -Url $CustomAgentUrl -Destination $CustomAgentPath

try {
    Write-Output "Installing Custom Agent..."
    # Adjust the arguments for silent installation as required by the installer
    Start-Process -FilePath $CustomAgentPath -ArgumentList "/quiet /norestart" -Wait -NoNewWindow
    Write-Output "Custom Agent installation completed."
}
catch {
    Write-Error "Installation of Custom Agent failed. Exception: $_"
    Stop-Transcript
    exit 1
}

# Finish logging
Stop-Transcript

Write-Output "Agent installation script completed successfully."
