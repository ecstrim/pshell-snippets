<#
Params needed
$ADMIN_PASSWORD
$DOMAIN_NAME

#>
# identify adds drive
$addsDriveLetter = ((Get-Volume | Where-Object { \$_.FileSystemLabel -eq 'ADDS' }).DriveLetter + ':')
$addsDBPath = Join-Path \$addsDriveLetter 'ADDS\DB'
$addsLogPath = Join-Path \$addsDriveLetter 'ADDS\LOG'
$sysvolPath = Join-Path \$addsDriveLetter 'ADDS\SYSVOL'
New-Item -Path $addsDBPath, $addsLogPath, $sysvolPath -ItemType Directory

$secureAdminPassword = ConvertTo-SecureString -String '$ADMIN_PASSWORD' -AsPlainText -Force
Install-ADDSForest `
  -DomainName $DOMAIN_NAME `
  -DomainNetbiosName (\$DOMAIN_NAME.Split('.')[0]) `
  -DomainMode WinThreshold `
  -ForestMode WinThreshold `
  -DatabasePath \$addsDBPath `
  -LogPath \$addsLogPath `
  -SysvolPath $sysvolPath `
  -InstallDns:$true `
  -SafeModeAdministratorPassword $secureAdminPassword `
  -NoRebootOnCompletion:$false `
  -Force:$true
