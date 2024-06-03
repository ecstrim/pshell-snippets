# log file 
$logPath = "$env:TEMP\clear-winupdatecache-log.txt"

# Function to write to the log
function Write-ToLog {
    param (
        [string]$message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $serverName = $env:COMPUTERNAME
    $logMessage = "$timestamp - $serverName - $message"

    Write-Host $logMessage
    Add-Content -Path $logPath -Value $logMessage
}

# Function to get the size of a folder
function Get-FolderSize {
    param (
        [string]$path
    )

    return (Get-ChildItem -Path $path -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
}

# Set the service to Manual start and log the operation
Set-Service -Name wuauserv -StartupType Manual
Write-ToLog "Set wuauserv service to Manual start."

# Stop the service and log the operation
Stop-Service -Name wuauserv -Force
Write-ToLog "Stopped wuauserv service."

# just to make sure the service is stopped
Start-Sleep -Seconds 5

$targetPath = "C:\Windows\SoftwareDistribution"
$renamedPath = "C:\Windows\SoftwareDistribution.old"

# Calculate and log the size of the SoftwareDistribution folder before renaming
$folderSizeBefore = Get-FolderSize -path $targetPath
Write-ToLog ("Size of SoftwareDistribution folder before renaming: {0:N2} MB" -f $folderSizeBefore)
# Rename the SoftwareDistribution folder and log the operation
Rename-Item -Path $targetPath -NewName "SoftwareDistribution.old"
Write-ToLog "Renamed SoftwareDistribution folder to SoftwareDistribution.old."

# Set the service to Automatic (Delayed Start) in the registry and log the operation
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv"
Set-ItemProperty -Path $regPath -Name Start -Value 2
Set-ItemProperty -Path $regPath -Name DelayedAutoStart -Value 1
Write-ToLog "Set wuauserv service to Automatic (Delayed Start)."

# Start the service and log the operation
Start-Service -Name wuauserv
Write-ToLog "Started wuauserv service."

# Wait for the original SoftwareDistribution folder to be recreated
Start-Sleep -Seconds 30

# Delete the renamed folder and log the operation
if ((Test-Path $renamedPath) -and (Test-Path $targetPath)) {
    Remove-Item -Path $renamedPath -Recurse -Force
    Write-ToLog "Deleted the renamed SoftwareDistribution.old folder."
}

# Calculate and log the size of the recreated SoftwareDistribution folder
$folderSizeAfter = Get-FolderSize -path $targetPath
Write-ToLog ("Size of SoftwareDistribution folder after resetting: {0:N2} MB" -f $folderSizeAfter)
