<#

Used to export NTFS permissions for huge shares (no I mean really really huge)
Directories only, no files

Uses .net libraries to keep memory consumption low

#>

$directory = '\\MYSERVER\Myshare'

$eDT = Get-Date
$eDateTimeCustom = [STRING]$eDT.Year + "-" + $("{0:D2}" -f $eDT.Month) + "-" + $("{0:D2}" -f $eDT.Day) + "_" + $("{0:D2}" -f $eDT.Hour) + "." + $("{0:D2}" -f $eDT.Minute) + "." + $("{0:D2}" -f $eDT.Second)

$csvPath = "C:\ACL-Export\NTFS_Permissions-$($eDateTimeCustom).csv"
$logPath = "C:\ACL-Export\NTFS_Permissions_Log-$($eDateTimeCustom).txt"



$StopWatch = [system.diagnostics.stopwatch]::startNew()
$StopWatch.Start()
$dirInfo = New-Object System.IO.DirectoryInfo($directory)
$folders = $dirInfo.GetDirectories("*", [System.IO.SearchOption]::AllDirectories)

foreach ($folder in $folders) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $message = "[$timestamp] Processing folder $($folder.FullName)"
    #Write-Host $message
    Add-Content -Path $logPath -Value $message
    
    $acl = Get-Acl $folder.FullName
    foreach ($ace in $acl.Access) {
        if (($ace.IdentityReference -ne "NT AUTHORITY\System") -and ($ace.IdentityReference -notlike "Builtin\*")) {
            $result = [ordered]@{
                Folder = $folder.FullName
                "User/Group" = $ace.IdentityReference
                Permissions = $ace.FileSystemRights
                AccessControlType = $ace.AccessControlType
                IdentityReference = $ace.IdentityReference
                IsInherited = $ace.IsInherited
                InheritanceFlags = $ace.InheritanceFlags
                PropagationFlags = $ace.PropagationFlags
            }
            [PSCustomObject]$result | Export-Csv -Path $csvPath -Append -NoTypeInformation -Encoding UTF8
        }
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$message = "[$timestamp] Finished processing subfolders."
Write-Host $message
Add-Content -Path $logPath -Value $message

$StopWatch.Stop()
Write-Host $StopWatch.Elapsed
Add-Content -Path $logPath -Value $StopWatch.Elapsed
