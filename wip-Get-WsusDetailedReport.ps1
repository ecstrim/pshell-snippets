$datetime = Get-Date -Format "yyyy.MM.dd_HH-mm-ss"
$domain = "domain.local"
$serverName = "wsus10.domain.local"
$file_name = "wsus_audit_result_" + $domain + "_" + $datetime + ".csv"
$xl_filename = "c:\audit\" + $file_name

[void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($serverName, $false)

$computerscope = New-Object Microsoft.UpdateServices.Administration.ComputerTargetScope
$computerscope.IncludeSubgroups = $true
$computerscope.IncludeDownstreamComputerTargets = $true
$computerscope.IncludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates] "Failed, NotInstalled, Downloaded"

$updates = $wsus.GetUpdates() | where { $_.IsApproved -eq $true }

$array = @{}
foreach ($update in $updates) {
    $temp = $update.GetUpdateInstallationInfoPerComputerTarget($ComputerScope) | ? { $_.UpdateApprovalAction -eq "Install" }
		
    if ($temp -ne $null) {
        foreach ($item in $temp) {
            $array.($wsus.GetComputerTarget([guid]$item.ComputerTargetId).FulldomainName)++
        }
    }
}

$export_array = @()
$export_array += , @(""); $export_array += , @("")

$i = 1
foreach ($key in $array.Keys) {
    if ($key.split(".")[1] -eq $domain.split(".")[0]) {
        $export_array += , @($key.Split(".")[0], $key.Split(".")[1], $array.$key)
    }
}

Write-Output "Saving report ..."
foreach ($item1 in $export_array) {  
    $csv_string = ""
    foreach ($item in $item1) {
        $csv_string = $csv_string + $item + ";"
    }
    Add-Content $xl_filename $csv_string
}