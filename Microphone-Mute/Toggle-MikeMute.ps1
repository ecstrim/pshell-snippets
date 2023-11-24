Import-Module AudioDeviceCmdlets
Import-Module BurntToast

$verbose = $false

# Function to get the current mute state
function Get-MicMuteState {
    return Get-AudioDevice -RecordingCommunicationMute
}

# Function to display the toast notification
function Show-ToastNotification($isMuted) {
    $muteStatus = if ($isMuted) { "Muted" } else { "Unmuted" }
    New-BurntToastNotification -Text "Microphone", $muteStatus
}

# Check initial mute state
$initialMuteState = Get-MicMuteState
if ( $verbose ) { Write-Host "Initial Mute State: $initialMuteState" }

# Toggle mute state
Set-AudioDevice -RecordingCommunicationMuteToggle

# Wait a bit to ensure the state has changed
#Start-Sleep -Seconds 1
Start-Sleep -Milliseconds 250

# Check new mute state
$finalMuteState = Get-MicMuteState
if ($verbose) { Write-Host "Final Mute State: $finalMuteState" }

# Show toast notification with the final state
Show-ToastNotification -isMuted $finalMuteState
