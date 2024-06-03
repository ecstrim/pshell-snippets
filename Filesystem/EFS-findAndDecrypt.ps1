#Requires -version 3.0

# DecryptAllFilesandFoldersOnLogicalDisk_v3.ps1
# Version 1.1
# By Marco Janse
# Last modified on Thursday, 16th of April 2015
# http://www.ictstuff.info/find-all-encrypted-files-and-folders-and-decrypt-them-using-powershell

# This script will scan for EFS encrypted files and folders on all logical drives and 
# decrypt them using a combination of PowerShell methods and the cipher utility.
# The script will log every step in a logfiles on C:Logs by default.


# START OF SCRIPT


# Verify the existence of a Logs directory. If it doesn not exist, create it.
If (-not(Test-Path -Path C:Logs))
    {
        New-Item -Path C: -Name Logs -ItemType directory
    }


# Date and Time
$today = Get-Date
$filename = $today.ToString("yyyy-MM-dd")
$logFile = "C:LogsEfsDecryptLog_$filename.log"


# Get al logical drives en put the output in a variabele named $drive
$drive = Get-WmiObject Win32_logicaldisk | Select-Object -ExpandProperty deviceID
Add-Content $logFile "$today Found the following drives: $drive"

# Let the user know the current status of the script
Write-Host "scanning all logical drives for encrypted files, please be patient..."

# Create a variable named $encryptedfiles that contains all items on all logical drives with a 'encrypted' attribute set

$encryptedfiles += foreach ($d in $drive) {
 
                    Get-ChildItem $d -File -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Attributes -match "Encrypted" } |
                    Select-Object -ExpandProperty FullName
                    }


# We will write to the logfile now log the amount of encrypted files and all the encrypted files with full pathname
Write-Host "Found $($encryptedfiles.count) encrypted files:"
Add-Content $logFile "$today Found $($encryptedfiles.count) encrypted files:"
Add-Content $logFile ""


foreach ($file in $encryptedfiles){
    Add-Content $logFile "$file"
    }

# Next we'll add some extra lines for easy reading the logfile
Add-Content $logFile "==============================================="
Add-Content $logFile "$today total $($encryptedfiles.count) encrypted files"
Add-Content $logfile ""

# Now, we'll start decrypting every file in the $encryptedfiles variable
Write-Host "starting decryption of all found files, please be patient..."

foreach ($file in $encryptedfiles) {
    try
    {
        (Get-Item $file).Decrypt()
        Add-Content $logFile "$file decrypted"
    }
    catch [Exception]
    {
        Add-Content $logFile "ERROR: Decrypting $file failed. Error message: $_.Exception.ToString()"
    }   
}

# Now we write a completed decrypting files status message to the logfile
Add-Content $logfile ""
Add-Content $logfile ""
Add-Content $logFile "Finished decrypting files"
Write-Host "Finished decrypting files"

# Next up, we want to remove the encrypted flag from all the folders as well
# We'll start by inventorying the encrypted folders again
Write-Host "scanning all logical drives for encrypted folders, please be patient..."

$encryptedfolders += foreach ($d in $drive) {
 
                    Get-ChildItem $d -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Attributes -match "Encrypted" } |
                    Select-Object -ExpandProperty FullName
                    }


# We will write to the logfile now log the amount of encrypted folders and all the encrypted folders with full pathname
Write-Host "Found $($encryptedfolders.count) encrypted folders:"
Add-Content $logFile "$today Found $($encryptedfolders.count) encrypted folders:"
Add-Content $logFile ""


foreach ($folder in $encryptedfolders){
    Add-Content $logFile "$folder"
    }

# Next we'll add some extra lines for easy reading the logfile
Add-Content $logFile "==============================================="
Add-Content $logFile "$today total $($encryptedfolders.count) encrypted folders"
Add-Content $logfile ""

# Now, we'll start decrypting every folder in the $encryptedfolders variable using the cipher utility
Write-Host "starting decryption of all found folders, please be patient..."

foreach ($folder in $encryptedfolders) {
    try
    {
        cipher.exe /d /i $folder
        Add-Content $logFile "$folder decrypted"
    }
    catch [Exception]
    {
        Add-Content $logFile "ERROR: Decrypting $folder failed. Error message: $_.Exception.ToString()"
    }   
}

# Finally, a closing message to the logfile
Add-Content $logfile ""
Add-Content $logfile ""
Add-Content $logFile "Finished decrypting folders"
Write-Host "Finished decrypting folders"
Add-Content $logfile ""
Add-Content $logfile ""
Add-Content $logFile "===END of script==="

Write-Host "===End of script==="

# END of Script
