# parse the sysvol from the PDC 
# check that every policy exists on the other dcs
# check for orphan gpos
Function Say($dataToLog, $lineType) {
	$datetimeLogLine = "[" + $(Get-Date -format "yyyy-MM-dd HH:mm:ss") + "] : "
	#Out-File -filepath "$logFilePath" -append -inputObject "$datetimeLogLine$dataToLog"
	#Write-Output($datetimeLogLine + $dataToLog)
	If ($null -eq $lineType) {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor Yellow
	}
	If ($lineType -eq "SUCCESS") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor Green
	}
	If ($lineType -eq "ERROR") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor Red
	}
	If ($lineType -eq "WARNING") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor Red
	}
	If ($lineType -eq "MAINHEADER") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor Magenta
	}
	If ($lineType -eq "HEADER") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor DarkCyan
	}
	If ($lineType -eq "REMARK") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor Cyan
	}
	If ($lineType -eq "REMARK-IMPORTANT") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor Green
	}
	If ($lineType -eq "REMARK-MORE-IMPORTANT") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor Yellow
	}
	If ($lineType -eq "REMARK-MOST-IMPORTANT") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor Red
	}
	If ($lineType -eq "ACTION") {
		Write-Host "$datetimeLogLine$dataToLog" -ForeGroundColor White
	}
	If ($lineType -eq "ACTION-NO-NEW-LINE") {
		Write-Host "$datetimeLogLine$dataToLog" -NoNewline -ForeGroundColor White
	}
}

$eDT = Get-Date
$eDateTimeCustom = [STRING]$eDT.Year + "-" + $("{0:D2}" -f $eDT.Month) + "-" + $("{0:D2}" -f $eDT.Day) + "_" + $("{0:D2}" -f $eDT.Hour) + "." + $("{0:D2}" -f $eDT.Minute) + "." + $("{0:D2}" -f $eDT.Second)

## find the boss
#Get the Fully Qualified Domain Name of the primary domain controller, which has the authoritative replica.
$pdcFQDN = Get-ADForest | Select-Object -ExpandProperty RootDomain | Get-ADDomain | Select-Object -ExpandProperty PDCEmulator
#Split out the machine name from the FQDN
$pdc = ($pdcFQDN -split '\.')[0]
#Get the domain name
$Domain = Get-ADForest | Select-Object -ExpandProperty Name

# find DCs
$DCs = Get-ADDomainController -Filter { name -ne $pdc } | Select-Object -ExpandProperty Name

Clear-Host

# check if SYSVOL is reachable on the PDC
$sysvolNetPathPDC = "\\$($pdc)\sysvol\$($Domain)\Policies\"
if ( Test-Path $sysvolNetPathPDC ) {
	Say "PDC SYSVOL share is accessible" "SUCCESS"
}
else {
	Say "*** ERROR : Cannot reach the SYSVOL share for $($pdc)" "ERROR"
	Exit 1
}

$pdcPolicies = $null
$pdcPolicies = Get-ChildItem -Path $sysvolNetPathPDC -Directory -Force | Where-Object { ($_.FullName -notlike "*_NTFRS_*") -and ($_.FullName -notlike "*Definitions*") } | Select-Object Name, LastWriteTime, CreationTime, FullName

Say "Found $($pdcPolicies.Count) policies"

# by fetching name i check if a gpo with the guid actually exists
# if not, means it is orphan
Say "Fetching names"
$pdcPoliciesGN = @()
$orphanGPOs = @()
foreach ($pdcPol in $pdcPolicies) {
	$pdcPolCleanGuid = ($pdcPol.Name -replace '{|}', '')
	$policyName = Get-Gpo -Guid $pdcPolCleanGuid -ErrorAction SilentlyContinue | Select-Object DisplayName
	if ( $policyName ) {
		$pdcPoliciesGN += [PSCustomObject]@{
			Name          = $policyName.DisplayName
			Id            = $pdcPol.Name
			LastWriteTime = $pdcPol.LastWriteTime
		}
	}
	else {
		$orphanGPOs += $pdcPol	
	}
}

Say "Testing SYSVOL network path on every DC"

$goodDCs = @()
$badDCs = @()
foreach ($dc in $DCs) {
	$dcSysvolPath = "\\$($dc)\SYSVOL\$($Domain)\Policies\"
	if ( Test-Path $dcSysvolPath ) {
		Say " $($dcSysvolPath) OK " "SUCCESS"
		$goodDCs += $dc
	}
	else {
		Say " $($dcPath) NOT ACCESSIBLE" "ERROR"
		$badDCs += $dc
	}
}

$allResults = $null
$allResults = New-Object -TypeName 'System.Collections.ArrayList'

Say ""
Say "Testing policies for every good DC"

$progressCounter = 0
$totalCount = $pdcPolicies.count

foreach ($item in $pdcPoliciesGN) {
	$progressCounter++
	Write-Progress -Activity 'Processing GPOs' -Id 1 -Status "Scanned: $progressCounter of $totalCount" -CurrentOperation $item.Name -PercentComplete(($progressCounter / $totalCount) * 100)

	$progressCounter2 = 0
	$totalCount2 = $goodDCs.count

	foreach ($dc in $goodDCs) {
		$progressCounter2++
		Write-Progress -Activity 'Checking on DC' -Id 2 -Status "Scanned: $progressCounter2 of $totalCount2" -CurrentOperation $dc -PercentComplete(($progressCounter2 / $totalCount2) * 100)

		$Exists = $null
		$dcPath = "\\$($dc)\SYSVOL\$($Domain)\Policies\$($item.Id)" 
		if ( Test-Path $dcPath ) {
			$Exists = $true
		}
		else {
			$Exists = $false
			$itemObj = [PSCustomObject]@{
				DC                = $dc
				Name              = $item.Name
				GUID              = $item.Id
				PDC_LastWriteTime = $item.LastWriteTime.ToString("yyy-MM-dd HH:mm")
				Exists            = $Exists
				Path              = $dcPath
			}
	
			$itemObj
			$null = $allResults.Add($itemObj)
		}
		
	}
}

Say " "
Say "---------------------------------------------------------------------------------------------------------------------"
Say " "
Write-Host " "

## $allResults | Export-Csv -Path ".\all-gpos-problems-$($eDateTimeCustom).csv" -NoTypeInformation -Encoding UTF8
$allResults

Say "Found $($allResults.Count) problems"

Say " "
Say "BAD DCs: " "REMARK-MORE-IMPORTANT"
$badDCs

Say " "
Say "ORPHAN GPOs (directory in sysvol without corresponding gpo): " "REMARK-MORE-IMPORTANT"
$orphanGPOs
