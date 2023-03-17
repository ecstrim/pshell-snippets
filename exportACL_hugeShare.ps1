<#

Export ACLs of all the folders in a huge share
Uses .Net libraries for performance and memory consumption reasons

.\exportACLS.ps1 -TargetPath '\\Server\Share\Dir' -DestinationPath 'C:\Temp'
#>
param (
    # target share in \\server\share\dir format
    [Parameter(Mandatory=$true)]
    [string]$TargetPath,

    # destination path
    [Parameter(Mandatory=$true)]
    [string]$DestinationPath
)

$StopWatch = [system.diagnostics.stopwatch]::startNew()
$StopWatch.Start()

$eDT = Get-Date
$eDateTimeCustom = [STRING]$eDT.Year + "-" + $("{0:D2}" -f $eDT.Month) + "-" + $("{0:D2}" -f $eDT.Day) + "_" + $("{0:D2}" -f $eDT.Hour) + "." + $("{0:D2}" -f $eDT.Minute) + "." + $("{0:D2}" -f $eDT.Second)
$csvPath = "$($DestinationPath)\NTFS_Permissions-$($eDateTimeCustom).csv"
$logPath = "$($DestinationPath)\NTFS_Permissions_Log-$($eDateTimeCustom).txt"
$logERR  = "$($DestinationPath)\NTFS_Permissions_Errors-$($eDateTimeCustom).txt"


## here be dragons --------------------------------------------------------------------
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$message = "[$timestamp] Starting"
Write-Host $message
Add-Content -Path $logPath -Value $message


$dirInfo = New-Object System.IO.DirectoryInfo($TargetPath)
$folders = $dirInfo.GetDirectories("*", [System.IO.SearchOption]::AllDirectories)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$message = "[$timestamp] Got the list of directories"
Write-Host $message
Add-Content -Path $logPath -Value $message

# Needed for the progress bar
$progressCounter = 0
$totalCount = $folders.count

foreach ($folder in $folders) {
    $progressCounter++
    Write-Progress -Activity 'Processing folders' -Status "Scanned: $progressCounter of $totalCount" -CurrentOperation $folder.FullName -PercentComplete(($progressCounter / $totalCount) * 100)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $message = "[$timestamp] Processing folder $($folder.FullName)"
    #Write-Host $message
    Add-Content -Path $logPath -Value $message
    
    $acl = Get-Acl $folder.FullName
    if ( $acl ) {
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
    } else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $message = "[$timestamp] Error on $($folder.FullName)"
        Add-Content -Path $logERR -Value $message
        $message = "[$timestamp] $($_.Exception.message)"
        Add-Content -Path $logERR -Value $message
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$message = "[$timestamp] Finished processing subfolders."
Write-Host $message
Add-Content -Path $logPath -Value $message

$StopWatch.Stop()
Write-Host $StopWatch.Elapsed
Add-Content -Path $logPath -Value $StopWatch.Elapsed
