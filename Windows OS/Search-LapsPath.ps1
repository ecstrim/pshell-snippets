# 
# find inactive computer accounts on all DCs
# 
Import-Module ActiveDirectory


$targetOU = "OU=LapsClients,DC=example,DC=loc"
$lapsPath = "\c$\Program Files\LAPS\CSE\AdmPwd.dll"


Clear-Host
# get computers in ou
$computers = Get-ADComputer -Filter { (Enabled -eq $True) } -ResultPageSize 2000 -ResultSetSize $null -SearchBase $targetOU -Properties * | Select-Object Name, DistinguishedName, IPv4Address, lastLogonDate, OperatingSystem, PasswordLastSet, ObjectGUID

$output = @()
$progressCounter = 0
$computersCount = $computers.count
# foreach test laps
foreach ($comp in $computers) {
    $progressCounter++
    Write-Progress -Activity 'Processing Computers' -Status "Scanned: $progressCounter of $computersCount" -CurrentOperation $comp.Name -PercentComplete(($progressCounter / $computersCount) * 100)
    $hasLaps = 'No'
    if (Test-Path "\\$($comp.Name)$($lapsPath)") {
        $hasLaps = 'Yes'
    }

    $output += [PSCustomObject]@{
        Name              = $comp.Name 
        HasLAPS           = $hasLaps 
        DistinguishedName = $comp.DistinguishedName 
        ObjectGUID        = $comp.ObjectGUID
        IPv4Address       = $comp.IPv4Address
        lastLogonDate     = $comp.lastLogonDate
        OperatingSystem   = $comp.OperatingSystem
        PasswordLastSet   = $comp.PasswordLastSet
    }
}

$output | Format-Table -AutoSize
