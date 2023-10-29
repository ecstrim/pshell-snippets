<#
.SYNOPSIS
This script disables the password complexity security policy and installs Active Directory Domain Services.

.DESCRIPTION
The script first creates and applies a security policy to disable password complexity.
It then identifies the ADDS drive based on a specified FileSystemLabel and creates directories for the ADDS database, logs, and SYSVOL.
Finally, it initiates the installation of an Active Directory forest.

.PARAMETER ADMIN_PASSWORD
The password for the domain administrator.

.PARAMETER DOMAIN_NAME
The name of the domain to be created.

.PARAMETER LOG_PATH
The path where the log file will be created.

.EXAMPLE
.\YourScriptName.ps1 -ADMIN_PASSWORD "P@ssw0rd" -DOMAIN_NAME "example.com" -LOG_PATH "C:\logs\script.log"

.NOTES
Ensure you run the script with elevated privileges as it modifies system security policies and installs ADDS.
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$ADMIN_PASSWORD,

    [Parameter(Mandatory=$true)]
    [string]$DOMAIN_NAME,

    [Parameter(Mandatory=$true)]
    [string]$LOG_PATH
)

function Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -Path $LOG_PATH
}

# Start logging
Log "Script started."

# disable password complexity security policy
Log "Disabling password complexity security policy..."
$content = @"
[Version]
signature="$CHICAGO$"

[System Access]
PasswordComplexity = 0
"@
$content | Out-File -Path C:\DisableComplexity.inf
secedit.exe /configure /db %windir%\security\local.sdb /cfg C:\DisableComplexity.inf /areas SECURITYPOLICY
Log "Password complexity security policy disabled."

# identify adds drive
Log "Identifying ADDS drive..."
$addsDriveLetter = ((Get-Volume | Where-Object { $_.FileSystemLabel -eq 'ADDS' }).DriveLetter + ':')
$addsDBPath = Join-Path $addsDriveLetter 'ADDS\DB'
$addsLogPath = Join-Path $addsDriveLetter 'ADDS\LOG'
$sysvolPath = Join-Path $addsDriveLetter 'ADDS\SYSVOL'
Log "ADDS drive identified as $addsDriveLetter."

# Create directories for ADDS
Log "Creating directories for ADDS..."
New-Item -Path $addsDBPath, $addsLogPath, $sysvolPath -ItemType Directory
Log "Directories for ADDS created."

# Install Active Directory Domain Services
Log "Initiating ADDS installation..."
$secureAdminPassword = ConvertTo-SecureString -String $ADMIN_PASSWORD -AsPlainText -Force
Install-ADDSForest `
  -DomainName $DOMAIN_NAME `
  -DomainNetbiosName ($DOMAIN_NAME.Split('.')[0]) `
  -DomainMode WinThreshold `
  -ForestMode WinThreshold `
  -DatabasePath $addsDBPath `
  -LogPath $addsLogPath `
  -SysvolPath $sysvolPath `
  -InstallDns:$true `
  -SafeModeAdministratorPassword $secureAdminPassword `
  -NoRebootOnCompletion:$false `
  -Force:$true
Log "ADDS installation initiated."

# End logging
Log "Script completed."
