<#
.SYNOPSIS
    PowerShell script to selectively backup directories modified in the last 24 hours using robocopy.
    
.DESCRIPTION
    This script scans the given source path for first-level and second-level directories. It identifies
    the directories that have been modified in the last 24 hours and backs them up to a specified destination 
    path using robocopy. It supports both dry-run mode for testing and actual execution.

    The script can also output the robocopy commands without executing them if desired, and logs all operations 
    to timestamped log files. Common system folders like 'recycle bin' and 'system volume information' are 
    automatically excluded from the backup process.

.PARAMETER path
    The source path where first-level directories are located.

.PARAMETER destinationPath
    The destination path where modified folders will be backed up.

.PARAMETER logFolder
    The folder path where log files will be stored. The script generates a centralized log file and individual
    robocopy logs for each operation.
    Default value is "C:\Logs".

.PARAMETER dryRun
    Enables or disables dry-run mode. If set to $true, the script will simulate the backup process without actually
    copying files (runs robocopy with the /L flag). Set this to $false for actual execution.
    Default value is $true (robocopy commands are generated in dry-run mode).

.PARAMETER outputOnly
    If set to $true, the script will output the robocopy commands without executing them. Useful for review.
    Default value is $true (output commands).

.PARAMETER hours
    Number of hours to look back for modified folders

.EXAMPLE
    .\BackupSyncScript.ps1 -path "X:\" -destinationPath "E:\NewBackup" -dryRun $false -outputOnly $true -hours 24
    Executes the script on directories located in "X:\", performs actual backup (no dry-run) to "E:\NewBackup", 
    and logs the process.

.NOTES
    This script excludes common system-related folders such as 'recycle bin' and 'system volume information'. 
    Ensure that you have the necessary permissions for the source and destination paths.

    Author: BOFH Llama
    Version: 1.0
    Date: September 2024
#>

param (
    [string]$path, # Source path
    [string]$destinationPath , # Destination path
    [string]$logFolder = "C:\Logs", # Log folder path
    [bool]$dryRun = $true, # Dry run mode, set to $false for actual sync
    [bool]$outputOnly = $true, # Only output the robocopy commands, no execution
    [int]$hours = 24 # Number of hours to look back for modified folders
)

# Ensure the log folder exists
if (-not (Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory | Out-Null
}

# Initialize the operations log file
$scriptLogFile = Join-Path $logFolder -ChildPath "ScriptOperationsLog_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Function to log messages to the operations log
function Write-Log {
    param (
        [string]$message,
        [string]$type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$type] - $message"
    # Append to operations log file
    Add-Content -Path $scriptLogFile -Value $logMessage
    # Also output to console
    Write-Host $logMessage
}

# Log the script start
Write-Log "Script started."

# Initialize an empty list to store directory details
$folderList = @()

# Excluded folder names (case-insensitive)
$excludedFolders = @('recycle bin', "system volume information", '$recycle.bin')

# Get first-level directories with Folder Name, Path, LastAccessTime, and LastWriteTime
try {
    $levelOneDirs = [System.IO.Directory]::GetDirectories($path)
    Write-Log "Retrieved first-level directories from $path."
    
    foreach ($dir in $levelOneDirs) {
        try {
            $dirInfo = [System.IO.DirectoryInfo]::new($dir)
            
            # Check if the directory should be excluded based on its name (case-insensitive comparison)
            if ($excludedFolders -contains $dirInfo.Name.ToLower()) {
                Write-Log "Excluded directory: $($dirInfo.Name)" "INFO"
                continue
            }

            # Add first-level directories to the list
            $folderList += [PSCustomObject]@{
                FolderName     = $dirInfo.Name
                Path           = $dirInfo.FullName
                LastAccessTime = $dirInfo.LastAccessTime
                LastWriteTime  = $dirInfo.LastWriteTime
                Level          = 1
            }

            # Get second-level directories inside each first-level directory
            $levelTwoDirs = [System.IO.Directory]::GetDirectories($dir)
            foreach ($subDir in $levelTwoDirs) {
                try {
                    $subDirInfo = [System.IO.DirectoryInfo]::new($subDir)
                    # Add second-level directories to the list
                    $folderList += [PSCustomObject]@{
                        FolderName     = $subDirInfo.Name
                        Path           = $subDirInfo.FullName
                        ParentFolder   = $dirInfo.Name   # Store the Level 1 parent folder name
                        LastAccessTime = $subDirInfo.LastAccessTime
                        LastWriteTime  = $subDirInfo.LastWriteTime
                        Level          = 2
                    }
                }
                catch {
                    Write-Log "Error accessing subdirectory $($subDir): $($_.Exception.Message)" "ERROR"
                }
            }

        }
        catch {
            Write-Log "Error accessing directory $($dir): $($_.Exception.Message)" "ERROR"
        }
    }
}
catch {
    Write-Log "Error accessing $($path): $($_.Exception.Message)" "ERROR"
}

# Output the list
Clear-Host
$folderList

# Get the current time
$currentTime = Get-Date

# Filter the folders that were modified in the last 24 hours (separately for Level 1 and Level 2)
$modifiedLevel1Folders = $folderList | Where-Object { $_.Level -eq 1 -and ($currentTime - $_.LastWriteTime).TotalHours -le $hours }
$modifiedLevel2Folders = $folderList | Where-Object { $_.Level -eq 2 -and ($currentTime - $_.LastWriteTime).TotalHours -le $hours }

# Function to either run or output robocopy command
function Run-Robocopy {
    param (
        [string]$source,
        [string]$destination,
        [string]$logFile,
        [int]$level
    )
    
    # Base robocopy command
    $robocopyCmd = "robocopy `"$source`" `"$destination`" /E /COPY:DATSO /R:2 /W:1 /MT:16 /LOG:`"$logFile`" /NP /V /TEE /XF `"~*`" "
    
    # Add /L flag for dry run if $dryRun is enabled
    if ($dryRun) {
        $robocopyCmd += " /L"
    }
    
    # If level 1, restrict recursion with /LEV:1
    if ($level -eq 1) {
        $robocopyCmd += " /LEV:1"
    }
    
    # Output or run the robocopy command based on $outputOnly
    if ($outputOnly) {
        Write-Host $robocopyCmd
    }
    else {
        try {
            Write-Log "Executing robocopy command: $robocopyCmd"
            Invoke-Expression $robocopyCmd
            Write-Log "Robocopy command for $source to $destination succeeded."
        }
        catch {
            Write-Log "Robocopy command for $source to $destination failed: $($_.Exception.Message)" "ERROR"
        }
    }
}

# Sync modified Level 2 folders first
foreach ($folder in $modifiedLevel2Folders) {
    $source = $folder.Path
    # Correctly include the parent Level 1 folder in the destination path
    $destination = Join-Path $destinationPath -ChildPath "$($folder.ParentFolder)\$($folder.FolderName)"
    
    # Generate a unique timestamped log file name
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFile = Join-Path $logFolder "$($folder.ParentFolder)_$($folder.FolderName)_$timestamp.log"
    
    # Run or output robocopy for Level 2 folders
    Run-Robocopy -source $source -destination $destination -logFile $logFile -level 2
}

# Now sync only the top-level content in Level 1 folders (ignore Level 2)
foreach ($folder in $modifiedLevel1Folders) {
    $source = $folder.Path
    $destination = Join-Path $destinationPath $folder.FolderName
    
    # Generate a unique timestamped log file name
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFile = Join-Path $logFolder "$($folder.FolderName)_$timestamp.log"
    
    # Run or output robocopy for Level 1 folders
    Run-Robocopy -source $source -destination $destination -logFile $logFile -level 1
}

# Log the script completion
Write-Log "Script completed successfully."
