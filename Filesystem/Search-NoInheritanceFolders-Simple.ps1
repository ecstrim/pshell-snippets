<#
.SYNOPSIS
Exports ACLs of directories with non-inherited access rules to text files (single-threaded version).

.DESCRIPTION
This script scans a specified target directory and its subdirectories for directories with non-inherited access control rules.
If such directories are found, their ACLs are exported to text files in a specified output directory. Additionally, a summary
of the processed directories is exported to a CSV file in the output directory.

This is the single-threaded version - simpler and with progress feedback. For large directory trees, consider using
Search-NoInheritanceFolders.ps1 which uses parallel processing.

.PARAMETER TargetDirectory
The path to the directory to scan for subdirectories.

.PARAMETER OutputDirectory
The path to the directory where the ACL export files and the summary CSV file will be saved. Defaults to 'C:\ACL_Exports' if not specified.

.EXAMPLE
.\Search-NoInheritanceFolders-Simple.ps1 -TargetDirectory "C:\Your\Target\Directory" -OutputDirectory "C:\Your\Output\Directory"
Scans 'C:\Your\Target\Directory' and exports ACLs with non-inherited rules to 'C:\Your\Output\Directory',
then creates a summary CSV file in the output directory.

.NOTES
Author: Mihai Olaru
Date: 2026-01-20
Version: 2.0
#>

param(
    [string]$TargetDirectory = "C:\Data",
    [string]$OutputDirectory = "C:\ACL_Exports"
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

# Collect errors to write at end
$accessDeniedErrors = [System.Collections.Generic.List[string]]::new()

# Define a recursive function for enumerating directories (outputs to pipeline for efficiency)
function Get-DirectoriesWithAccess {
    param (
        [System.IO.DirectoryInfo]$Directory,
        [System.Collections.Generic.List[string]]$AccessDeniedList
    )

    Try {
        $subDirectories = $Directory.GetDirectories()
        foreach ($subDir in $subDirectories) {
            Try {
                Write-Output $subDir
                Get-DirectoriesWithAccess -Directory $subDir -AccessDeniedList $AccessDeniedList
            }
            Catch {
                $errorMessage = "Access denied to directory: $($subDir.FullName)"
                Write-Warning $errorMessage
                $AccessDeniedList.Add($errorMessage)
            }
        }
    }
    Catch {
        $errorMessage = "Access denied to directory: $($Directory.FullName)"
        Write-Warning $errorMessage
        $AccessDeniedList.Add($errorMessage)
    }
}

# Start directory enumeration - include target directory itself
Write-Host "Enumerating directories..." -ForegroundColor Cyan
$directories = @($directoryInfo) + @(Get-DirectoriesWithAccess -Directory $directoryInfo -AccessDeniedList $accessDeniedErrors)
Write-Host "Found $($directories.Count) directories to process" -ForegroundColor Cyan

# Create MD5 hasher instance
$md5 = [System.Security.Cryptography.MD5]::Create()
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

Try {
    $processedCount = 0
    $totalCount = $directories.Count

    foreach ($dir in $directories) {
        $processedCount++

        # Show progress
        if ($processedCount % 100 -eq 0 -or $processedCount -eq $totalCount) {
            $percentComplete = [math]::Round(($processedCount / $totalCount) * 100, 1)
            Write-Progress -Activity "Scanning directories for non-inherited ACLs" `
                -Status "Processing $processedCount of $totalCount ($percentComplete%)" `
                -PercentComplete $percentComplete `
                -CurrentOperation $dir.FullName
        }

        Try {
            $acl = Get-Acl $dir.FullName
            $anyRuleNotInherited = $acl.Access | Where-Object { -not $_.IsInherited }

            if ($anyRuleNotInherited) {
                # Handle root directories where Parent may be null
                $parentPath = if ($null -ne $dir.Parent) { $dir.Parent.FullName } else { "" }
                $data = [System.Text.Encoding]::UTF8.GetBytes($parentPath)
                $hash = [System.BitConverter]::ToString($md5.ComputeHash($data)).Replace("-", "").Substring(0, 10)
                $outputFileName = "{0}_{1}.txt" -f $dir.Name, $hash
                $outputPath = Join-Path $OutputDirectory $outputFileName
                $null = icacls $dir.FullName /C /save $outputPath

                $results.Add([PSCustomObject]@{
                    ExportFileName = $outputFileName
                    ParentPath     = $parentPath
                })
            }
        }
        Catch {
            $errorMessage = "Failed to process directory: $($dir.FullName). Error: $_"
            Write-Warning $errorMessage
            $accessDeniedErrors.Add($errorMessage)
        }
    }
}
Finally {
    Write-Progress -Activity "Scanning directories for non-inherited ACLs" -Completed
    if ($md5) { $md5.Dispose() }
}

# Write all errors to log file at once
if ($accessDeniedErrors.Count -gt 0) {
    $accessDeniedErrors | Set-Content -Path $accessDeniedLog
}

# Export results to CSV
$results | Export-Csv -Path (Join-Path $OutputDirectory "Directories_Export.csv") -NoTypeInformation

# Output results and total execution time
$executionTime = (Get-Date) - $startTime
Write-Output ""
Write-Output ("Total Execution Time: {0:00} hours, {1:00} minutes, {2:00} seconds" -f $executionTime.Hours, $executionTime.Minutes, $executionTime.Seconds)
Write-Output "Directories scanned: $($directories.Count)"
Write-Output "Directories with non-inherited ACLs found: $($results.Count)"
Write-Output "CSV with directory export info saved to $(Join-Path $OutputDirectory 'Directories_Export.csv')"
if ($accessDeniedErrors.Count -gt 0) {
    Write-Output "Access denied errors ($($accessDeniedErrors.Count)) logged to $accessDeniedLog"
}

