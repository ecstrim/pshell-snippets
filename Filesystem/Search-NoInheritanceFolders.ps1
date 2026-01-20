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
Date: 2026-01-20
Version: 2.0
#>

param(
    [string]$TargetDirectory = "C:\Data", 
    [string]$OutputDirectory = "C:\ACL_Exports" # Default value if not specified
)

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
        $null = New-Item -Path $OutputDirectory -ItemType Directory -ErrorAction Stop
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

# Define a recursive function for enumerating directories (outputs to pipeline for efficiency)
function Get-DirectoriesWithAccess {
    param (
        [System.IO.DirectoryInfo]$Directory,
        [System.Collections.Generic.List[string]]$AccessDeniedList
    )

    Try {
        # Get all subdirectories
        $subDirectories = $Directory.GetDirectories()
        foreach ($subDir in $subDirectories) {
            # Try accessing each subdirectory
            Try {
                Write-Output $subDir  # Output to pipeline instead of array concatenation
                Get-DirectoriesWithAccess -Directory $subDir -AccessDeniedList $AccessDeniedList
            }
            Catch {
                # Collect access-denied directories
                $errorMessage = "Access denied to directory: $($subDir.FullName)"
                Write-Warning $errorMessage
                $AccessDeniedList.Add($errorMessage)
            }
        }
    }
    Catch {
        # Collect if the top-level directory can't be accessed
        $errorMessage = "Access denied to directory: $($Directory.FullName)"
        Write-Warning $errorMessage
        $AccessDeniedList.Add($errorMessage)
    }
}

# Initialize list to collect access denied errors (thread-safe for later use)
$accessDeniedErrors = [System.Collections.Generic.List[string]]::new()

# Start directory enumeration - include target directory itself, then enumerate subdirectories
$directories = @($directoryInfo) + @(Get-DirectoriesWithAccess -Directory $directoryInfo -AccessDeniedList $accessDeniedErrors)

# Define the script block to execute for each directory
$scriptBlock = {
    param($dir, $OutputDirectory)
    $md5 = $null
    Try {
        $acl = Get-Acl $dir.FullName
        $anyRuleNotInherited = $acl.Access | Where-Object { -not $_.IsInherited }

        if ($anyRuleNotInherited) {
            $md5 = [System.Security.Cryptography.MD5]::Create()
            # Handle root directories where Parent may be null
            $parentPath = if ($null -ne $dir.Parent) { $dir.Parent.FullName } else { "" }
            $data = [System.Text.Encoding]::UTF8.GetBytes($parentPath)
            $hash = [System.BitConverter]::ToString($md5.ComputeHash($data)).Replace("-", "").Substring(0, 10)
            $outputFileName = "{0}_{1}.txt" -f $dir.Name, $hash
            $outputPath = Join-Path $OutputDirectory $outputFileName
            $null = icacls $dir.FullName /C /save $outputPath

            return [PSCustomObject]@{
                ExportFileName = $outputFileName
                ParentPath     = $parentPath
                Error          = $null
            }
        }
    }
    Catch {
        # Return error instead of writing to shared file (avoids race condition)
        return [PSCustomObject]@{
            ExportFileName = $null
            ParentPath     = $null
            Error          = "Failed to process directory: $($dir.FullName). Error: $_"
        }
    }
    Finally {
        if ($md5) { $md5.Dispose() }
    }
    return $null
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

Try {
    # Runspace pool setup
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
    $runspacePool.Open()
    $jobs = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($dir in $directories) {
        if ($null -ne $dir) {
            $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($dir).AddArgument($OutputDirectory)
            $powershell.RunspacePool = $runspacePool
            $jobs.Add([PSCustomObject]@{ Pipe = $powershell; Status = $powershell.BeginInvoke() })
        }
    }

    foreach ($job in $jobs) {
        $result = $job.Pipe.EndInvoke($job.Status)
        if ($null -ne $result) {
            # Collect errors separately
            if ($result.Error) {
                Write-Warning $result.Error
                $accessDeniedErrors.Add($result.Error)
            }
            elseif ($result.ExportFileName) {
                $results.Add($result)
            }
        }
        $job.Pipe.Dispose()
    }
}
Finally {
    # Clean up runspace pool
    if ($runspacePool) {
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
}

# Write all access denied errors to log file at once (avoids race conditions)
if ($accessDeniedErrors.Count -gt 0) {
    $accessDeniedErrors | Set-Content -Path $accessDeniedLog
}

# Export results to CSV (exclude Error property from output)
$results | Select-Object ExportFileName, ParentPath | Export-Csv -Path (Join-Path $OutputDirectory "Directories_Export.csv") -NoTypeInformation

# Stop timing execution
$executionTime = (Get-Date) - $startTime

# Output results and total execution time
Write-Output ("Total Execution Time: {0:00} hours, {1:00} minutes, {2:00} seconds" -f $executionTime.Hours, $executionTime.Minutes, $executionTime.Seconds)
Write-Output "Directories with non-inherited ACLs found: $($results.Count)"
Write-Output "CSV with directory export info saved to $(Join-Path $OutputDirectory 'Directories_Export.csv')"
if ($accessDeniedErrors.Count -gt 0) {
    Write-Output "Access denied errors ($($accessDeniedErrors.Count)) logged to $accessDeniedLog"
}
