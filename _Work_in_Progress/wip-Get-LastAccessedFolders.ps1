# Define the path and number of days (90 days for the last 3 months)
$path = "C:\Your\Path\Here"
$daysThreshold = 90  # This represents 3 months (you can adjust if needed)

# Get the current date
$currentDate = Get-Date

# Get all first-level directories
$firstLevelFolders = Get-ChildItem -Path $path -Directory

# Loop through each first-level folder
foreach ($firstLevelFolder in $firstLevelFolders) {
    # Get all second-level directories inside each first-level folder
    $secondLevelFolders = Get-ChildItem -Path $firstLevelFolder.FullName -Directory
    
    foreach ($secondLevelFolder in $secondLevelFolders) {
        $lastAccessTime = (Get-Item $secondLevelFolder.FullName).LastAccessTime
        
        # Calculate the difference in days between now and the last access time
        $daysSinceLastAccess = ($currentDate - $lastAccessTime).Days
        
        # If the folder has been accessed in the last 90 days, output the folder details
        if ($daysSinceLastAccess -le $daysThreshold) {
            Write-Output "$($secondLevelFolder.FullName) was accessed $daysSinceLastAccess days ago."
        }
    }
}

#-----------------------

# Define the path
$path = "C:\Your\Path\Here"

# Get all first-level directories
$folders = Get-ChildItem -Path $path -Directory

# Loop through each folder and calculate the size
foreach ($folder in $folders) {
    $folderPath = $folder.FullName
    
    # Calculate folder size in bytes
    $folderSizeBytes = (Get-ChildItem -Path $folderPath -Recurse | Measure-Object -Property Length -Sum).Sum
    
    # Convert size to GB
    $folderSizeGB = [math]::Round($folderSizeBytes / 1GB, 2)
    
    # Output folder name and size
    Write-Output "$($folder.Name) : $folderSizeGB GB"
}
