# Get the string we want to search for 
$string = "ClearTextPassword" 
 
# Set the domain to search for GPOs 
$DomainName = $env:USERDNSDOMAIN 
 
# Find all GPOs in the current domain 
Write-Host "Searching all the GPOs in $DomainName" 
Import-Module grouppolicy 
$allGposInDomain = Get-GPO -All -Domain $DomainName 
[string[]] $MatchedGPOList = @()

# Look through each GPO's XML for the string 
Write-Host "Starting search...." 
foreach ($gpo in $allGposInDomain) { 
    $report = Get-GPOReport -Guid $gpo.Id -ReportType Xml 
    if ($report -match $string) { 
        write-host "********** Match found in: $($gpo.DisplayName) **********" -foregroundcolor "Green"
        $MatchedGPOList += "$($gpo.DisplayName)";
    }
} # end foreach

Write-Host "`r`n"
Write-Host "Results: **************" -foregroundcolor "Yellow"
foreach ($match in $MatchedGPOList) { 
    write-host "Match found in: $($match)" -foregroundcolor "Green"
}
