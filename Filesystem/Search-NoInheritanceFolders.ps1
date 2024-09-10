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
Version: 1.0

#>
param(
    [string]$TargetDirectory, 
    [string]$OutputDirectory = "C:\ACL_Exports" # Default value if not specified
)

# Load required assemblies
Add-Type -AssemblyName System.Security

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

# Enumerate all directories recursively
Try {
    $directories = $directoryInfo.EnumerateDirectories("*", [System.IO.SearchOption]::AllDirectories)
}
Catch {
    Write-Error "Error enumerating directories: $_"
    exit 1
}

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
        Write-Output "Failed to process directory: $dir. Error: $_"
    }
    return $null
}

# Create a single instance of the MD5 hasher
$md5 = [System.Security.Cryptography.MD5]::Create()

Try {
    # Initialize DirectoryInfo object for the target directory
    $directoryInfo = New-Object System.IO.DirectoryInfo($TargetDirectory)

    # Enumerate all directories recursively using .NET directly
    $directories = $directoryInfo.EnumerateDirectories("*", [System.IO.SearchOption]::AllDirectories)

    # Runspace pool setup
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
    $runspacePool.Open()
    $jobs = @()

    foreach ($dir in $directories) {
        $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($dir).AddArgument($md5).AddArgument($OutputDirectory)
        $powershell.RunspacePool = $runspacePool
        $jobs += [PSCustomObject]@{ Pipe = $powershell; Status = $powershell.BeginInvoke() }
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
    if ($runspacePool) {
        $runspacePool.Close()
    }
    if ($md5) {
        $md5.Dispose()
    }
}

# Export results to CSV
$filteredResults = $results | Where-Object { $_ -ne $null }
$filteredResults | Export-Csv -Path (Join-Path $OutputDirectory "Directories_Export.csv") -NoTypeInformation

# Convert milliseconds to a TimeSpan and format it
$timeSpan = [TimeSpan]::FromMilliseconds($executionTime.TotalMilliseconds)
$hours = $timeSpan.Hours.ToString("00")
$minutes = $timeSpan.Minutes.ToString("00")
$seconds = $timeSpan.Seconds.ToString("00")

# Output results and total execution time
Write-Output "Total Execution Time: $hours hours, $minutes minutes, $seconds seconds"
Write-Output "CSV with directory export info saved to $(Join-Path $OutputDirectory 'Directories_Export.csv')"
