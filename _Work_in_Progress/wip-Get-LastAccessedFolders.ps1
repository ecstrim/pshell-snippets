# Define the path and number of days of inactivity
$path = "C:\Your\Path\Here"
$daysThreshold = 365  # Change this to the number of days to check for

# Get the current date
$currentDate = Get-Date

# Get all first-level directories
$folders = Get-ChildItem -Path $path -Directory

# Loop through each folder and check the last access time
foreach ($folder in $folders) {
    $lastAccessTime = (Get-Item $folder.FullName).LastAccessTime
    
    # Calculate the difference in days
    $daysSinceLastAccess = ($currentDate - $lastAccessTime).Days
    
    # If the folder hasn't been accessed within the threshold, output the folder details
    if ($daysSinceLastAccess -gt $daysThreshold) {
        Write-Output "$($folder.Name) was last accessed $daysSinceLastAccess days ago."
    }
}
