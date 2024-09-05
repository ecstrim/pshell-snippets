# Define the path and number of days of inactivity
$path = "C:\Your\Path\Here"
$daysThreshold = 365  # Change this to the number of days to check for

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
        
        # Calculate the difference in days
        $daysSinceLastAccess = ($currentDate - $lastAccessTime).Days
        
        # If the second-level folder hasn't been accessed within the threshold, output the folder details
        if ($daysSinceLastAccess -gt $daysThreshold) {
            Write-Output "$($secondLevelFolder.FullName) was last accessed $daysSinceLastAccess days ago."
        }
    }
}
