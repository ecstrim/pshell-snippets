$RegPath1       = 'HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center\Notifications'
$KeyA1_Name     = 'DisableNotifications'
$KeyA2_Name     = 'DisableEnhancedNotifications'

$RegPath2       = 'HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center\Virus and threat protection'
$KeyB1_Name     = 'SummaryNotificationDisabled'
$KeyB2_Name     = 'NoActionNotificationDisabled'
$KeyB3_Name     = 'FilesBlockedNotificationDisabled'

# 0 - Enable Notifications
# 1 - Disable Notifications
$Value = 0

# get keys
Get-ItemPropertyValue -Path $RegPath1 -Name $KeyA1_Name
Get-ItemPropertyValue -Path $RegPath1 -Name $KeyA2_Name
Get-ItemPropertyValue -Path $RegPath2 -Name $KeyB1_Name
Get-ItemPropertyValue -Path $RegPath2 -Name $KeyB2_Name
Get-ItemPropertyValue -Path $RegPath2 -Name $KeyB3_Name

# Now set keys
Set-ItemProperty -Path $RegPath1 -Name $KeyA1_Name -Value $Value -Force
Set-ItemProperty -Path $RegPath1 -Name $KeyA2_Name -Value $Value -Force
Set-ItemProperty -Path $RegPath2 -Name $KeyB1_Name -Value $Value -Force
Set-ItemProperty -Path $RegPath2 -Name $KeyB2_Name -Value $Value -Force
Set-ItemProperty -Path $RegPath2 -Name $KeyB3_Name -Value $Value -Force
