$path = "Z:\Elba3"

# Initialize a List to store directory details
$folderList = [System.Collections.Generic.List[PSObject]]::new()

# Excluded folders (case-insensitive)
$excludedFolders = @("Recycle Bin", "System Volume Information")

# Calculate the date threshold (90 days ago)
$dateThreshold = (Get-Date).AddDays(-90)

# Get first-level directories with Folder Name, Path, LastAccessTime, and LastWriteTime
try {
    $levelOneDirs = [System.IO.Directory]::GetDirectories($path)
    
    foreach ($dir in $levelOneDirs) {
        try {
            $dirInfo = [System.IO.DirectoryInfo]::new($dir)
            
            # Ignore excluded directories (case-insensitive comparison)
            if ($excludedFolders -ieq $dirInfo.Name) {
                continue
            }

            # Only add if LastWriteTime is within the last 90 days
            if ($dirInfo.LastWriteTime -gt $dateThreshold) {
                # Add first-level directories to the list
                $folderList.Add([PSCustomObject]@{
                        FolderName     = $dirInfo.Name
                        Path           = $dirInfo.FullName
                        LastAccessTime = $dirInfo.LastAccessTime
                        LastWriteTime  = $dirInfo.LastWriteTime
                    })
            }

            # Get second-level directories inside each first-level directory
            $levelTwoDirs = [System.IO.Directory]::GetDirectories($dir)
            foreach ($subDir in $levelTwoDirs) {
                try {
                    $subDirInfo = [System.IO.DirectoryInfo]::new($subDir)

                    # Only add if LastWriteTime is within the last 90 days
                    if ($subDirInfo.LastWriteTime -gt $dateThreshold) {
                        # Add second-level directories to the list
                        $folderList.Add([PSCustomObject]@{
                                FolderName     = $subDirInfo.Name
                                Path           = $subDirInfo.FullName
                                LastAccessTime = $subDirInfo.LastAccessTime
                                LastWriteTime  = $subDirInfo.LastWriteTime
                            })
                    }
                }
                catch {
                    Write-Host "Error accessing subdirectory $($subDir): $_" -ForegroundColor Magenta
                }
            }

        }
        catch {
            Write-Host "Error accessing directory $($dir): $_" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "Error accessing $($path): $($_)" -ForegroundColor Red
}

# Output the list or show a message if it's empty
if ($folderList.Count -eq 0) {
    Write-Host "No directories modified in the last 90 days." -ForegroundColor Yellow
}
else {
    $folderList
    Write-Host "Processed $($folderList.Count) directories modified in the last 90 days." -ForegroundColor Green
}
