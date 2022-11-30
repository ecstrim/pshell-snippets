
# using $searchBase on line 10
#param (
#    [Parameter(Mandatory = $false)][string]$SearchBase
#)

Import-Module ActiveDirectory

# set target ou if not using param
$SearchBase = "OU=LapsClients,DC=example,DC=loc"

$output = @()
## list OUs in the search path
$allOUS = Get-ADOrganizationalUnit -Filter * -SearchBase $SearchBase -SearchScope OneLevel | Select-Object -Property Name, DistinguishedName

foreach ($ounit in $allOUS) {
    $ouComputers = @(Get-ADComputer -Filter * -SearchBase $ounit.DistinguishedName -properties ms-mcs-admpwdexpirationtime | Select-Object Name, DistinguishedName, ms-mcs-admpwdexpirationtime)
    $xxComputers = @($ouComputers | Where-Object { ($_."ms-mcs-admpwdexpirationtime") })

    $lapsCount = $xxComputers.Count
    $computersCount = $ouComputers.Count
    $percentage = 0
    if ( $lapsCount -gt 0 -And $computersCount -gt 0 ) {
        $percentage = ($lapsCount / $omputersCount) * 100
    }

    $output += [PSCustomObject]@{
        percentage          = percentage
        lapsCount           = $lapsCount
        computersCount      = $computersCount
        OUName              = $ounit.Name 
        OUDistinguishedName = $ounit.DistinguishedName
    }
}

$output | Select-Object percentage, lapsCount, computersCount, Name | Sort-Object lapsCount -Descending |  Format-Table -AutoSize
