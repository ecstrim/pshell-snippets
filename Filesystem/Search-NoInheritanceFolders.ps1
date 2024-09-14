<#
.SYNOPSIS
Exports ACLs of directories with non-inherited access rules to text files.

.DESCRIPTION
This script scans a specified target directory and its subdirectories for directories with non-inherited access control rules.
If such directories are found, their ACLs are exported to text files in a specified output directory. Additionally, a summary
of the processed directories is exported to a CSV file in the output directory.

.PARAMETER TargetDirectory
The path to the directory to scan for subdirectories.

.PARAMETER OutputDirectory
The path to the directory where the ACL export files and the summary CSV file will be saved. Defaults to 'C:\ACL_Exports' if not specified.

.EXAMPLE
.\Search-NoInheritanceFolders.ps1 -TargetDirectory "C:\Your\Target\Directory" -OutputDirectory "C:\Your\Output\Directory"
Scans 'C:\Your\Target\Directory' and exports ACLs with non-inherited rules to 'C:\Your\Output\Directory', 
then creates a summary CSV file in the output directory.

.NOTES
Author: Mihai Olaru
Date: 2024-06-03
Version: 1.3
#>

param(
    [string]$TargetDirectory, 
    [string]$OutputDirectory = "C:\ACL_Exports" # Default value if not specified
)

# Load required assemblies
Add-Type -AssemblyName System.Security

# Start timing execution
$startTime = Get-Date

# Validate the existence of the TargetDirectory
if (-not (Test-Path -Path $TargetDirectory -PathType Container)) {
    Write-Error "The specified target directory does not exist: $TargetDirectory"
    exit 1
}

# Validate the OutputDirectory and create if it does not exist
if (-not (Test-Path -Path $OutputDirectory)) {
    Try {
        New-Item -Path $OutputDirectory -ItemType Directory -ErrorAction Stop
    }
    Catch {
        Write-Error "Failed to create output directory at: $OutputDirectory. Error: $_"
        exit 1
    }
}

# Initialize DirectoryInfo object for the target directory
$directoryInfo = New-Object System.IO.DirectoryInfo($TargetDirectory)

# Log file for directories without access
$accessDeniedLog = Join-Path $OutputDirectory "AccessDeniedLog.txt"

# Define a recursive function for enumerating directories
function Get-DirectoriesWithAccess {
    param (
        [System.IO.DirectoryInfo]$Directory
    )
    
    $directories = @()
    Try {
        # Get all subdirectories
        $subDirectories = $Directory.GetDirectories()
        foreach ($subDir in $subDirectories) {
            # Try accessing each subdirectory
            Try {
                $directories += $subDir
                $directories += Get-DirectoriesWithAccess -Directory $subDir  # Recursively check subdirectories
            }
            Catch {
                # Log access-denied directories
                $errorMessage = "Access denied to directory: $($subDir.FullName)"
                Write-Warning $errorMessage
                Add-Content -Path $accessDeniedLog -Value $errorMessage
            }
        }
    }
    Catch {
        # Log if the top-level directory can't be accessed
        $errorMessage = "Access denied to directory: $($Directory.FullName)"
        Write-Warning $errorMessage
        Add-Content -Path $accessDeniedLog -Value $errorMessage
    }
    return $directories
}

# Start directory enumeration
$directories = Get-DirectoriesWithAccess -Directory $directoryInfo

# Define the script block to execute for each directory
$scriptBlock = {
    param($dir, $md5, $OutputDirectory)
    Try {
        $acl = $dir.GetAccessControl()
        $anyRuleNotInherited = $acl.Access | ForEach-Object { -not $_.IsInherited } -contains $true

        if ($anyRuleNotInherited) {
            $data = [System.Text.Encoding]::UTF8.GetBytes($dir.Parent.FullName)
            $hash = [System.BitConverter]::ToString($md5.ComputeHash($data)).Replace("-", "").Substring(0, 10)
            $outputFileName = "{0}_{1}.txt" -f $dir.Name, $hash
            $outputPath = Join-Path $OutputDirectory $outputFileName
            $null = (icacls $dir.FullName /C /save $outputPath)

            return [PSCustomObject]@{
                ExportFileName = $outputFileName
                ParentPath     = $dir.Parent.FullName
            }
        }
    }
    Catch {
        $errorMessage = "Failed to process directory: $($dir.FullName). Error: $_"
        Write-Warning $errorMessage
        Add-Content -Path $accessDeniedLog -Value $errorMessage
    }
    return $null
}

# Create a single instance of the MD5 hasher
$md5 = [System.Security.Cryptography.MD5]::Create()

Try {
    # Runspace pool setup
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
    $runspacePool.Open()
    $jobs = @()

    foreach ($dir in $directories) {
        if ($dir -ne $null) {
            $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($dir).AddArgument($md5).AddArgument($OutputDirectory)
            $powershell.RunspacePool = $runspacePool
            $jobs += [PSCustomObject]@{ Pipe = $powershell; Status = $powershell.BeginInvoke() }
        }
    }

    $results = @()
    foreach ($job in $jobs) {
        $result = $job.Pipe.EndInvoke($job.Status)
        if ($result) {
            $results += $result
        }
        $job.Pipe.Dispose()
    }
}
Finally {
    # Clean up runspace pool and MD5 hasher
    if ($runspacePool) {
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
    if ($md5) {
        $md5.Dispose()
    }
}

# Export results to CSV
$filteredResults = $results | Where-Object { $_ -ne $null }
$filteredResults | Export-Csv -Path (Join-Path $OutputDirectory "Directories_Export.csv") -NoTypeInformation

# Stop timing execution
$endTime = Get-Date
$executionTime = $endTime - $startTime

# Convert milliseconds to a TimeSpan and format it
$timeSpan = [TimeSpan]::FromMilliseconds($executionTime.TotalMilliseconds)
$hours = $timeSpan.Hours.ToString("00")
$minutes = $timeSpan.Minutes.ToString("00")
$seconds = $timeSpan.Seconds.ToString("00")

# Output results and total execution time
Write-Output "Total Execution Time: $hours hours, $minutes minutes, $seconds seconds"
Write-Output "CSV with directory export info saved to $(Join-Path $OutputDirectory 'Directories_Export.csv')"
Write-Output "Access denied directories logged to $accessDeniedLog"
