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

Clear-Host 

## some stuff
$eDT = Get-Date
$eDateTimeCustom = [STRING]$eDT.Year + "-" + $("{0:D2}" -f $eDT.Month) + "-" + $("{0:D2}" -f $eDT.Day) + "_" + $("{0:D2}" -f $eDT.Hour) + "." + $("{0:D2}" -f $eDT.Minute) + "." + $("{0:D2}" -f $eDT.Second)

Write-Host " "
Write-Host " "
Write-Host " "
Write-Host " "
Write-Host " "


#Get the domain name
$Domain = Get-ADForest | Select-Object -ExpandProperty Name

$DCs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty Name
## $DCs = @("DCHQ", "DCHQ02", "DCNL1")

$allGPOS = $null
$allPOLS = $null
$allGPOS = New-Object -TypeName 'System.Collections.ArrayList'
$allPOLS = New-Object -TypeName 'System.Collections.ArrayList'

$badDCs = @()

$orphanedGPOS = @()
$orphanedPOLS = @()

## get GPOs from AD
## get Policies from SYSVOL
$progressCounter = 0
$totalCount = $DCs.count
foreach ($dc in $DCs) {
    $GPOs = $null 
    $POLs = $null

    $progressCounter++
    Write-Progress -Activity 'Processing DC' -Id 1 -Status "Scanned: $progressCounter of $totalCount" -CurrentOperation $dc -PercentComplete(($progressCounter / $totalCount) * 100)


    Say " "
    Say "Processing [$($dc)]"

    $GPOs = Get-GPO -All -Server $dc | Select-Object Id, Displayname, CreationTime, ModificationTime, GpoStatus, @{Label = "ComputerVersion"; Expression = { $_.computer.dsversion } }, @{Label = "UserVersion"; Expression = { $_.user.dsversion } }
    $allGPOs += [PSCustomObject]@{
        DC   = $dc
        GPOs = $GPOs
    }
    Say " - Found $($GPOs.Count) GPOs in AD" "SUCCESS"

    $dcSysvolPath = "\\$($dc)\SYSVOL\$($Domain)\Policies\"
    if ( Test-Path $dcSysvolPath ) {
        #Say " $($dcSysvolPath) OK " "SUCCESS"

        $POLs = Get-ChildItem -Path $dcSysvolPath -Directory -Force | Where-Object { ($_.FullName -notlike "*_NTFRS_*") -and ($_.FullName -notlike "*Definitions*") } | Select-Object Name, @{Label = "LastWriteTime"; Expression = { $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } }, @{Label = "CreationTime"; Expression = { $_.CreationTime.ToString("yyyy-MM-dd HH:mm:ss") } }, FullName
        Say " - Found $($POLs.Count) policies in SYSVOL" "SUCCESS"
        $allPOLS += [PSCustomObject]@{
            DC   = $dc
            POLs = $POLs
        }
    }
    else {
        Say " $($dcPath) NOT ACCESSIBLE" "ERROR"
        $badDCs += $dc
    }

    ## let's check for orphans
    $countDiff = ($GPOs.Count - $POLs.Count) 
    if ($countDiff -gt 0) {
        ## 
        Say "GPO $($countDiff) " "MAINHEADER"
        ## find out the orphaned GPO
        foreach ($gpo in $GPOs) {
            $gpoId = -join ("{", $gpo.Id, "}")
            $exist = $POLS | Where-Object { $_.Name -eq $gpoId }
            if ( $exist ) {
                ## @todo test this $Exist
                ## Say " $($gpo.Name) OK"

            }
            else {
                Say " $($gpo.Name) orphaned " "ERROR"
                $orphanedGPOS += [PSCustomObject]@{
                    DC  = $dc
                    GPO = $gpo
                }
            }
        }
    }
    elseif ($countDiff -lt 0) {
        ## there are more policies
        Say "Policies $($countDiff)"  "MAINHEADER"
        ## find the orphaned Policy
        foreach ($pol in $POLs) {
            $gpoId = $pol.Name -replace '{|}', ''
            $exist = $GPOS | Where-Object { $_.Id -eq $gpoId }
            if ( $exist ) {
                ## Say " $($exist.Name) OK"
            }
            else {
                $orphanPolicyPath = "\\$($dc)\SYSVOL\$($Domain)\Policies\$($pol.Name)"
                Say " $($pol.Name) orphaned " "ERROR"
                Say $orphanPolicyPath "WARNING"
                Say " "

                $orphanedPOLS += [PSCustomObject]@{
                    DC  = $dc
                    POL = $pol
                }
            }
        }
    }
    else {
        ## nodiff
        Say "No diff!" "SUCCESS"
    }
}

## Compare the stuff

#Compare-Object $allGPOS[0].GPOs $allGPOS[1].GPOs
#Compare-Object $allPOLS[0].POLs $allPOLS[1].POLs

## $allGPOS  | ConverTo-JSON -Depth 5 
## $allPOLS  | ConverTo-JSON -Depth 5
## $orphanedGPOS | ConverTo-JSON -Depth 5
## $orphanedPOLS | ConverTo-JSON -Depth 5 | Out-File "C:\Batch\Orphaned-SYSVOL-Policies-$($eDateTimeCustom).txt"
