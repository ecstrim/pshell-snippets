$DCs = Get-ADDomainController -Filter *
$logName = "Security"
$eventID = 4624
$output = @()

foreach ($dc in $DCs) {
    Write-Host "Checking NTLMv1 usage on $($dc.HostName)..."
    $events = Get-WinEvent -ComputerName $dc.HostName -LogName $logName | Where-Object {
        $_.Id -eq $eventID -and $_.Properties[10].Value -match "NTLMv1"
    }

    if ($events) {
        foreach ($event in $events) {
            $output += [PSCustomObject]@{
                DomainController = $dc.HostName
                TimeCreated      = $event.TimeCreated
                UserName         = $event.Properties[5].Value
                IPAddress        = $event.Properties[18].Value
            }
        }
        Write-Host "NTLMv1 usage detected on $($dc.HostName)"
    }
    else {
        Write-Host "No NTLMv1 usage on $($dc.HostName)"
    }
}

$output | Export-Csv -Path "NTLMv1_Usage_Report.csv" -NoTypeInformation
Write-Host "Report saved to NTLMv1_Usage_Report.csv"


#---

$logName = "Security"
$eventID = 4624
$output = @()

Write-Host "Checking NTLMv1 usage on this Domain Controller..."
$events = Get-WinEvent -LogName $logName | Where-Object {
    $_.Id -eq $eventID -and $_.Properties[10].Value -match "NTLMv1"
}

if ($events) {
    foreach ($event in $events) {
        $output += [PSCustomObject]@{
            TimeCreated = $event.TimeCreated
            UserName    = $event.Properties[5].Value
            IPAddress   = $event.Properties[18].Value
        }
    }
    Write-Host "NTLMv1 usage detected."
}
else {
    Write-Host "No NTLMv1 usage found."
}

$output | Export-Csv -Path "NTLMv1_Usage_Report_DC.csv" -NoTypeInformation
Write-Host "Report saved to NTLMv1_Usage_Report_DC.csv"
