# Define log directory
$logDir = "C:\path\to\logs"

# Define output file
$outputFile = "C:\path\to\output.txt"

# Get all log files in the log directory
$logFiles = Get-ChildItem -Path $logDir -Filter "*.log"

# Initialize total failed files and directories counters
$totalFailedFiles = 0
$totalFailedDirs = 0

# Iterate through each log file
foreach ($logFile in $logFiles) {
    # Parse log file for statistics
    $stats = Select-String -Path $logFile.FullName -Pattern "^\s*Dirs\s*:\s*\d+" -Context 0, 12

    # Extract the number of failed files and directories from the statistics
    $failedDirs = ($stats.Context.PostContext[0] -split '\s+')[5]
    $failedFiles = ($stats.Context.PostContext[1] -split '\s+')[5]

    # Add the numbers of failed files and directories to the total counters
    $totalFailedDirs += [int]$failedDirs
    $totalFailedFiles += [int]$failedFiles

    # Output log file name, statistics, and numbers of failed files and directories to the output file
    "`nLog file: $($logFile.Name)" | Out-File -Append $outputFile
    $stats.Line | Out-File -Append $outputFile
    $stats.Context.PostContext | Out-File -Append $outputFile
    "Number of failed directories: $failedDirs" | Out-File -Append $outputFile
    "Number of failed files: $failedFiles" | Out-File -Append $outputFile
}

# Output total number of failed directories and files to the output file
"`nTotal number of failed directories: $totalFailedDirs" | Out-File -Append $outputFile
"`nTotal number of failed files: $totalFailedFiles" | Out-File -Append $outputFile
