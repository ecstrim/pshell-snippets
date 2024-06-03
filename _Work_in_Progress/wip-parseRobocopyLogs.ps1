# Define the folder where your log files are stored
$logFolder = "Path_to_your_log_folder"

# Define the file where the results should be stored
$outputFile = "Path_to_output_file.csv"

# Define the delimiter for the output file
$delimiter = ","

# Create an array to hold the results
$results = @()

# Initialize totals
$totalDirs = $totalFiles = $totalBytes = @{
    'Total'    = 0
    'Copied'   = 0
    'Skipped'  = 0
    'Mismatch' = 0
    'Failed'   = 0
    'Extras'   = 0
}

# Get a list of the log files in the folder
$logFiles = Get-ChildItem -Path $logFolder -Filter "*.log"

# Loop through each log file
foreach ($logFile in $logFiles) {
    # Read the contents of the log file
    $logContent = Get-Content -Path $logFile.FullName

    # Find the lines with the statistics
    $statLines = $logContent | Where-Object { $_ -like "    Dirs :*" -or $_ -like "   Files :*" -or $_ -like "   Bytes :*" -or $_ -like "   Times :*" }

    # Create a custom object to hold the stats for this log file
    $logStats = New-Object PSObject
    $logStats | Add-Member -MemberType NoteProperty -Name "LogFileName" -Value $logFile.Name

    # Parse the statistics and add them to the custom object
    foreach ($line in $statLines) {
        $splitLine = $line -split "\s+"
        $label = $splitLine[1]
        $total = $splitLine[3]
        $copied = $splitLine[5]
        $skipped = $splitLine[7]
        $mismatch = $splitLine[9]
        $failed = $splitLine[11]
        $extras = $splitLine[13]

        # Add to totals
        $totalDirs[$label] += $total -as [int]
        $totalFiles[$label] += $copied -as [int]
        $totalBytes[$label] += $skipped -as [int]

        $logStats | Add-Member -MemberType NoteProperty -Name "$label-Total" -Value $total
        $logStats | Add-Member -MemberType NoteProperty -Name "$label-Copied" -Value $copied
        $logStats | Add-Member -MemberType NoteProperty -Name "$label-Skipped" -Value $skipped
        $logStats | Add-Member -MemberType NoteProperty -Name "$label-Mismatch" -Value $mismatch
        $logStats | Add-Member -MemberType NoteProperty -Name "$label-Failed" -Value $failed
        $logStats | Add-Member -MemberType NoteProperty -Name "$label-Extras" -Value $extras
    }

    # Add the stats for this log file to the results array
    $results += $logStats
}

# Add totals to results
$results += New-Object PSObject -Property @{
    'LogFileName'    = 'Total'
    'Dirs-Total'     = $totalDirs['Total']
    'Dirs-Copied'    = $totalDirs['Copied']
    'Dirs-Skipped'   = $totalDirs['Skipped']
    'Dirs-Mismatch'  = $totalDirs['Mismatch']
    'Dirs-Failed'    = $totalDirs['Failed']
    'Dirs-Extras'    = $totalDirs['Extras']
    'Files-Total'    = $totalFiles['Total']
    'Files-Copied'   = $totalFiles['Copied']
    'Files-Skipped'  = $totalFiles['Skipped']
    'Files-Mismatch' = $totalFiles['Mismatch']
    'Files-Failed'   = $totalFiles['Failed']
    'Files-Extras'   = $totalFiles['Extras']
    'Bytes-Total'    = $totalBytes['Total']
    'Bytes-Copied'   = $totalBytes['Copied']
    'Bytes-Skipped'  = $totalBytes['Skipped']
    'Bytes-Mismatch' = $totalBytes['Mismatch']
    'Bytes-Failed'   = $totalBytes['Failed']
    'Bytes-Extras'   = $totalBytes['Extras']
}

# Export the results to a CSV file
$results | Export-Csv -Path $outputFile -Delimiter $delimiter -NoTypeInformation
