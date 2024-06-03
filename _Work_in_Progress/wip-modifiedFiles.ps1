# Define the path and number of days
$Path = 'C:\Your\Path\Here' # Change this to your directory path
$Days = 4 # Modify this to change the number of days to look back

$Destination = 'C:\Path\modified-files.csv' # full path and file name

# Get the current date
$CurrentDate = [System.DateTime]::Now

# Get the date 'x' days ago
$Date = $CurrentDate.AddDays(-$Days)

# Get a list of files in the specified directory
$Files = [System.IO.Directory]::GetFiles($Path, '*.*', [System.IO.SearchOption]::AllDirectories)

$ModifiedFilesList = @() # Array to hold file info objects

foreach ($File in $Files) {
    # Get the FileInfo object
    $FileInfo = New-Object System.IO.FileInfo($File)

    # Get the last write time of the file
    $LastWriteTime = $FileInfo.LastWriteTime

    # If the file was modified in the last 'x' days, add its info to the list
    if ($LastWriteTime -gt $Date) {
        $ModifiedFilesList += New-Object PSObject -Property @{
            'FileName'        = $File
            'LastModified'    = $LastWriteTime
            'FileSizeInBytes' = $FileInfo.Length
        }
    }
}

# Export the list of modified files to a CSV file
$ModifiedFilesList | Export-Csv -Path $Destination -NoTypeInformation -Encoding UTF8
