# Define the base paths for the source, destination, and log file locations
$sourceBase = "X:\TechOper"     
$destinationBase = "G:\Elba1\TechOper"
$logFile = "C:\Sync"                  

# Function to start a robocopy job with full paths and timestamped log file
function Start-RobocopyJob {
    param (
        [string]$sourceFolder, # Folder name relative to base paths
        [string]$logFileName          # Base name for the log file
    )

    # Build full source and destination paths
    $source = "$sourceBase\$sourceFolder"
    $destination = "$destinationBase\$sourceFolder"

    # Create a timestamp for the log file name
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    # Full robocopy command
    $robocopyCommand = "robocopy `"$source`" `"$destination`" /E /COPY:DATSO /R:2 /W:1 /MT:16 /LOG:`"$logFile\$logFileName-$timestamp.log`" /NP /V /XF `~*`" "
    
    # Start the robocopy job in the background
    Start-Job -ScriptBlock { Invoke-Expression $using:robocopyCommand } -Name $logFileName
}

# Start robocopy jobs for each folder
Start-RobocopyJob -sourceFolder "EHS-2017" -logFileName "EHS-2017"
Start-RobocopyJob -sourceFolder "Industrial Development & Product Allocation" -logFileName "Industrial_Development"
Start-RobocopyJob -sourceFolder "Sicurezza Aziendale" -logFileName "Sicurezza_Aziendale"
Start-RobocopyJob -sourceFolder "Tecnical Operations" -logFileName "Tecnical_Operations"
Start-RobocopyJob -sourceFolder "Beltrami" -logFileName "Beltrami"

# Display the list of running jobs
Get-Job
