$logDir = ".\samples\"
# Define output file
$outputFile = ".\samples\output.txt"

Clear-Host
# Get all log files in the log directory
$logFiles = Get-ChildItem -Path $logDir -Filter "*.log"

# Initialize total failed files and directories counters
$totalFailedFiles = 0
$totalFailedDirs = 0

# Iterate through each log file
foreach ($log in $logFiles) {
    # Extract the source path
    $sourcePath = (Select-String -Path $log.FullName -Pattern "Source : .+" | ForEach-Object { ($_ -split " : ")[-1] }).ToString().Trim()
    
    # Extract the start and end times using Select-String
    $startTimeString = (Select-String -Path $log.FullName -Pattern "Started : .+" | ForEach-Object { ($_ -split " : ")[-1] }).ToString().Trim()
    $endTimeString = (Select-String -Path $log.FullName -Pattern "Ended : .+" | ForEach-Object { ($_ -split " : ")[-1] }).ToString().Trim()

    # Parse the times
    $startTime = [DateTime]::ParseExact($startTimeString, "dddd, MMMM dd, yyyy hh:mm:ss tt", $null)
    $endTime = [DateTime]::ParseExact($endTimeString, "dddd, MMMM dd, yyyy hh:mm:ss tt", $null)
    # Calculate the elapsed time
    $elapsedTime = $endTime - $startTime

    # Parse log file for statistics
    $stats = Select-String -Path $log.FullName -Pattern "^\s*Total\s*Copied\s*Skipped\s*Mismatch\s*FAILED\s*Extras" -Context 0, 5

    # Extract the number of failed files and directories from the statistics
    $failedDirs = ($stats.Context.PostContext[0] -split '\s+')[7]
    $failedFiles = ($stats.Context.PostContext[1] -split '\s+')[7]

    # Add the numbers of failed files and directories to the total counters
    $totalFailedDirs += [int]$failedDirs
    $totalFailedFiles += [int]$failedFiles

    # Output log file name, statistics, and numbers of failed files and directories to the output file
    "`nLog file: $($log.Name)"  | Out-File -Append $outputFile
    "Source path: $sourcePath" | Out-File -Append $outputFile
    "---------------------------------------------------------------------" | Out-File -Append $outputFile
    # Write-Output "---------------------------------------------------------------------"
    # $stats.Line
    # $stats.Context.PostContext
    # Write-Output "---------------------------------------------------------------------"
    $stats.Line | Out-File -Append $outputFile
    $stats.Context.PostContext | Out-File -Append $outputFile
    "---------------------------------------------------------------------" | Out-File -Append $outputFile

    "Failed directories: $failedDirs" | Out-File -Append $outputFile
    "Failed files: $failedFiles" | Out-File -Append $outputFile
    "Total time taken: {0}" -f $elapsedTime.ToString() | Out-File -Append $outputFile
    
}