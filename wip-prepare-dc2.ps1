<#
.SYNOPSIS
This script creates DC2

.DESCRIPTION
do not use

.PARAMETER ADMIN_PASSWORD
The password for the domain administrator.

.PARAMETER DOMAIN_NAME
The name of the domain to be created.

.PARAMETER LOG_PATH
The path where the log file will be created.

.EXAMPLE
.\wip-prepare-dc1.ps1 -ADMIN_PASSWORD "P@ssw0rd" -DOMAIN_NAME "example.com" -LOG_PATH "C:\logs\script.log"

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
    "$timestamp - $Message" | Out-File -Append -FilePath $LOG_PATH
}

# Start logging
Log "[DC2] Script started."

# identify adds drive
Log "[DC2] Identifying ADDS drive..."
$addsDriveLetter = ((Get-Volume | Where-Object { $_.FileSystemLabel -eq 'ADDS' }).DriveLetter + ':')
$addsDBPath = Join-Path $addsDriveLetter 'ADDS\DB'
$addsLogPath = Join-Path $addsDriveLetter 'ADDS\LOG'
$sysvolPath = Join-Path $addsDriveLetter 'ADDS\SYSVOL'
Log "ADDS drive identified as $addsDriveLetter."

# Install Active Directory Domain Services
Log "[DC2] Initiating ADDS installation..."
# $secureAdminPassword = ConvertTo-SecureString -String $ADMIN_PASSWORD -AsPlainText -Force

$cred = (New-Object System.Management.Automation.PSCredential ("$DOMAIN_NAME\\$VM_LOCAL_ADMIN_USER", (ConvertTo-SecureString -String "$VM_LOCAL_ADMIN_PASSWORD" -AsPlainText -Force)))
Add-Computer -DomainName $DOMAIN_NAME -Credential $cred
Install-ADDSDomainController -DomainName $DOMAIN_NAME -Credential $cred -DatabasePath $addsDBPath -LogPath $addsLogPath -SysvolPath $sysvolPath -InstallDns:$true -NoRebootOnCompletion:$false -Force:$true
Log "[DC2] ADDS installation initiated."

# End logging
Log "[DC2] cript completed."
