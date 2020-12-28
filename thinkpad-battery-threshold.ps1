## YOU MUST CHANGE THIS FOR YOUR SPECIFIC LAPTOP - Battery serial number as shown in Lenovo Companion battery info. 
$BattSerial = "<battery_serial>" 

## charging start percentage
$StartP = "75"

## charging stop percentage
$StopP = "90"

$val = Get-ItemProperty -Path hklm:software\WOW6432Node\Lenovo\PWRMGRV\ConfKeys\Data\$BattSerial -Name "ChargeStartControl"
if($val.ChargeStartControl -ne 1)
{
 set-itemproperty -Path hklm:software\WOW6432Node\Lenovo\PWRMGRV\ConfKeys\Data\$BattSerial -Name "ChargeStartControl" -value 1
}

$val = Get-ItemProperty -Path hklm:software\WOW6432Node\Lenovo\PWRMGRV\ConfKeys\Data\$BattSerial -Name "ChargeStopControl"
if($val.ChargeStopControl -ne 1)
{
 set-itemproperty -Path hklm:software\WOW6432Node\Lenovo\PWRMGRV\ConfKeys\Data\$BattSerial -Name "ChargeStopControl" -value 1
}

$val = Get-ItemProperty -Path hklm:software\WOW6432Node\Lenovo\PWRMGRV\ConfKeys\Data\$BattSerial -Name "ChargeStartPercentage"
if($val.ChargeStartPercentage -ne $StartP)
{
 set-itemproperty -Path hklm:software\WOW6432Node\Lenovo\PWRMGRV\ConfKeys\Data\$BattSerial -Name "ChargeStartPercentage" -value $StartP
}

$val = Get-ItemProperty -Path hklm:software\WOW6432Node\Lenovo\PWRMGRV\ConfKeys\Data\$BattSerial -Name "ChargeStopPercentage"
if($val.ChargeStopPercentage -ne $StopP)
{
 set-itemproperty -Path hklm:software\WOW6432Node\Lenovo\PWRMGRV\ConfKeys\Data\$BattSerial -Name "ChargeStopPercentage" -value $StopP
}
