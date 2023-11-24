Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\AudioSwitcher.AudioApi.3.0.0\lib\net40\AudioSwitcher.AudioApi.dll"
[AudioSwitcher.AudioApi.AudioController].GetConstructors()

# Create a new AudioController instance
$audioController = New-Object AudioSwitcher.AudioApi.AudioController

# Get the default recording device
$recordingDevice = $audioController.DefaultCaptureDevice

# Toggle mute
$recordingDevice.Mute(!$recordingDevice.IsMuted)



[Reflection.Assembly]::LoadFile("C:\Program Files\PackageManagement\NuGet\Packages\AudioSwitcher.AudioApi.3.0.0\lib\net40\AudioSwitcher.AudioApi.dll")
[Reflection.Assembly]::LoadFrom("C:\Program Files\PackageManagement\NuGet\Packages\AudioSwitcher.AudioApi.3.0.0\lib\net40\AudioSwitcher.AudioApi.dll").GetTypes() | Select FullName



$audioController = New-Object -TypeName "AudioSwitcher.AudioApi.CoreAudio.CoreAudioController"
