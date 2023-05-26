# Define log directory
$logDir = "C:\path\to\logs"

# Define output file
$outputFile = "C:\path\to\output.txt"

# Get all log files in the log directory
$logFiles = Get-ChildItem -Path $logDir -Filter "*.log"

# Initialize total failed files counter
$totalFailedFiles = 0

# Iterate through each log file
foreach ($logFile in $logFiles) {
    # Parse log file for statistics
    $stats = Select-String -Path $logFile.FullName -Pattern "^\s*Total\s*Copied\s*Skipped\s*Mismatch\s*FAILED\s*Extras" -Context 0, 15

    # Extract the number of failed files from the statistics
    $failedFiles = ($stats.Context.PostContext[4] -split '\s+')[5]

    # Add the number of failed files to the total counter
    $totalFailedFiles += $failedFiles

    # Output log file name, statistics, and number of failed files to the output file
    "`nLog file: $($logFile.Name)" | Out-File -Append $outputFile
    $stats.Line | Out-File -Append $outputFile
    $stats.Context.PostContext | Out-File -Append $outputFile
    "Number of failed files: $failedFiles" | Out-File -Append $outputFile
}

# Output total number of failed files to the output file
"`nTotal number of failed files: $totalFailedFiles" | Out-File -Append $outputFile
