$query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_USBControllerDevice'"
Register-WmiEvent -Query $query -SourceIdentifier USBDeviceAdded -Action {
    Write-Host "USB device connected"
}

$query = "SELECT * FROM __InstanceDeletionEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_USBControllerDevice'"
Register-WmiEvent -Query $query -SourceIdentifier USBDeviceRemoved -Action {
    Write-Host "USB device disconnected"
}

# Prevent the script from exiting
while ($true) {
    Start-Sleep -Seconds 10
}
