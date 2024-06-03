# Author : Nitish Kumar
# Performs an audit of WSUS
# Outputs the results to a text file.
# version 1.2
# 21 May 2017

[void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")

$firstdayofmonth = [datetime] ([string](get-date).AddMonths(-1).month + "/1/" + [string](get-date).year)
$DomainName = "." + $env:USERDNSDOMAIN

# Create empty arrays to contain collected data.
$UpdateStatus = @()
$SummaryStatus = @()

# For WSUS servers catering servers
$WSUSServers = ("XYZ", "ABC")

$a0 = ($WSUSServers | measure).count
$b0 = 0

$thisDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = "WSUSAuditReports_$((Get-Date).ToString('MM-dd-yyyy_hh-mm-ss')).txt"
Start-Transcript -Path $thisDir\$logFile

ForEach ($WS1 in $WSUSServers) {
    write-host "Working on $WS1 ..."	-foregroundcolor Green
    $b0 = $b0 + 1

    try {

        Try {
            $WSUS = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($WS1, $false, 8530)
        }
        Catch {
            $WSUS = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($WS1, $false, 80)
        }

        $ComputerScope = New-Object Microsoft.UpdateServices.Administration.ComputerTargetScope
        $UpdateScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $UpdateScope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved
        $updatescope.IncludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::All

        $ComputerTargetGroups = $WSUS.GetComputerTargetGroups() | Where { $_.Name -eq 'All Computers' }
        $MemberOfGroup = $WSUS.getComputerTargetGroup($ComputerTargetGroups.Id).GetComputerTargets()

        write-host "Connected and Fetching the data from $WS1 for all computers connecting to it..."
        $Alldata = $WSUS.GetSummariesPerComputerTarget($updatescope, $computerscope)
        $a = ($Alldata | measure).count
        $b = 0

        write-host "Data recieved from $WS1 for all computers connecting to it..."
        Foreach ($Object in $Alldata) {
            $b = $b + 1
            write-host "Getting data from number $b of all $a computers connecting to $WS1 ($b0 of $a0)..."	-foregroundcolor Yellow
            Foreach ($object1 in $MemberOfGroup) {
                If ($object.computertargetid -match $object1.id) {

                    $ComputerTargetToUpdate = $WSUS.GetComputerTargetByName($object1.FullDomainName)
                    $NeededUpdate = $ComputerTargetToUpdate.GetUpdateInstallationInfoPerUpdate() | where { ($_.UpdateApprovalAction -eq "install") -and (($_.UpdateInstallationState -eq "Downloaded") -or ($_.UpdateInstallationState -eq "Notinstalled") -or ($_.UpdateInstallationState -eq "Failed"))	}

                    $FailedUpdateReport = @()
                    $NeededUpdateReport = @()
                    $NeededUpdateDateReport = @()

                    if ($NeededUpdate -ne $null) {
                        foreach ($Update in $NeededUpdate) {
                            $NeededUpdateReport += ($WSUS.GetUpdate([Guid]$Update.updateid)).KnowledgebaseArticles
                            $NeededUpdateDateReport += ($WSUS.GetUpdate([Guid]$Update.updateid)).ArrivalDate.ToString("dd/MM/yyyy ")
                        }
                    }

                    $object1 | select -ExpandProperty FullDomainName
                    $myObject1 = New-Object -TypeName PSObject
                    $myObject1 | add-member -type Noteproperty -Name Server -Value (($object1 | select -ExpandProperty FullDomainName) -replace $DomainName, "")
                    $myObject1 | add-member -type Noteproperty -Name NotInstalledCount -Value $object.NotInstalledCount
                    $myObject1 | add-member -type Noteproperty -Name NotApplicable -Value $object.NotApplicableCount
                    $myObject1 | add-member -type Noteproperty -Name DownloadedCount -Value $object.DownloadedCount
                    $myObject1 | add-member -type Noteproperty -Name InstalledCount -Value $object.InstalledCount
                    $myObject1 | add-member -type Noteproperty -Name InstalledPendingRebootCount -Value $object.InstalledPendingRebootCount
                    $myObject1 | add-member -type Noteproperty -Name FailedCount -Value $object.FailedCount
                    $myObject1 | add-member -type Noteproperty -Name NeededCount -Value ($NeededUpdate | measure).count
                    $myObject1 | add-member -type Noteproperty -Name Needed -Value $NeededUpdateReport
                    $myObject1 | add-member -type Noteproperty -Name LastSyncTime -Value $object1.LastSyncTime
                    $myObject1 | add-member -type Noteproperty -Name IPAddress -Value $object1.IPAddress
                    $myObject1 | add-member -type Noteproperty -Name OS -Value $object1.OSDescription
                    $myObject1 | add-member -type Noteproperty -Name NeededDate -Value $NeededUpdateDateReport
                    $SummaryStatus += $myObject1
                }
            }
        }

        $SummaryStatus | select-object server, NeededCount, LastSyncTime, InstalledPendingRebootCount, NotInstalledCount, DownloadedCount, InstalledCount, FailedCount, @{Name = "KB Numbers"; Expression = { $_.Needed } }, @{Name = "Arrival Date"; Expression = { $_.NeededDate } }, NotApplicable, IPAddress, OS | export-csv -notype $Env:Userprofile\desktop\AllServersStatus.csv

        write-host "Connected with $WS1 and finding patches for last month schedule .."
        # Find patches from 1st day of (M-2) month to 2nd Monday of (M-1) month
        $updatescope.FromArrivalDate = [datetime](get-date).Addmonths(-2).AddDays( - ((Get-date).day - 1))

        $updatescope.ToArrivalDate = [datetime](0..31 | % { $firstdayofmonth.adddays($_) } | ? { $_.dayofweek -like "Mon*" })[1]
        #[datetime](0..31 | % {$firstdayofmonth.adddays($_) } | ? {$_.dayofweek -like "Mon*"})[1]

        $file1 = "$env:userprofile\desktop\Currentmonthupdates_" + $WS1 + ".csv"
        $WSUS.GetSummariesPerUpdate($updatescope, $computerscope) | select-object @{L = 'UpdateTitle'; E = { ($WSUS.GetUpdate([guid]$_.UpdateId)).Title } }, @{L = 'Arrival Date'; E = { ($WSUS.GetUpdate([guid]$_.UpdateId)).ArrivalDate } }, @{L = 'KB Article'; E = { ($WSUS.GetUpdate([guid]$_.UpdateId)).KnowledgebaseArticles } }, @{L = 'NeededCount'; E = { ($_.DownloadedCount + $_.NotInstalledCount) } }, DownloadedCount, NotApplicableCount, NotInstalledCount, InstalledCount, FailedCount | Export-csv -Notype $file1

    }
    catch [Exception] {
        write-host $_.Exception.GetType().FullName -foregroundcolor Red
        write-host $_.Exception.Message -foregroundcolor Red
        continue
    }
}