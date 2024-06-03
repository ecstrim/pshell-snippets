<#
.SYNOPSIS
  Export NTFS permissions (ACL) 
.DESCRIPTION
  Intended for huge shared folders
  Uses .NET libraries where possible to minimize memory consumption
  The ususal PowerShell cmdlets were too hungry (Get-ChildItem & Get-ACL)
.PARAMETER TargetPath
    Mandatory, path to scan for NTFS permissions
.PARAMETER TargetPath
    Mandatory, path for the output files
.INPUTS
  None
.OUTPUTS
  CSV file stored in $DestinationPath\ACL-Export-<timestamp>.log
  Log file stored in $DestinationPath\ACL-Export-Log-<timestamp>.log
  Error paths log file stored in $DestinationPath\ACL-Export-Errors-<timestamp>.log
  Access denied paths log file stored in $DestinationPath\ACL-Export-Denied-<timestamp>.log
.NOTES
  Version:        1.2
  Author:         Mihai Olaru
  Creation Date:  2023-03-18
  Purpose/Change: Initial script development
  
.EXAMPLE
  .\exportACLS_heavy.ps1 -TargetPath "\\Server\Share\Folder" -DestinationPath "C:\Temp"
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$TargetPath,

    [Parameter(Mandatory=$true)]
    [string]$DestinationPath
)

# Load required .NET libraries
Add-Type -AssemblyName System.IO

$StopWatch = [system.diagnostics.stopwatch]::startNew()
$StopWatch.Start()

Write-Output "* Starting, this may take a while..."

$eDT = Get-Date
$tsCustom = [STRING]$eDT.Year + "-" + $("{0:D2}" -f $eDT.Month) + "-" + $("{0:D2}" -f $eDT.Day) + "_" + $("{0:D2}" -f $eDT.Hour) + "." + $("{0:D2}" -f $eDT.Minute) + "." + $("{0:D2}" -f $eDT.Second)

$ExportPath = "$($DestinationPath)\ACL-Export-$($tsCustom).csv"
$LogPath    = "$($DestinationPath)\ACL-Export-Log-$($tsCustom).log"
$ErrorPath  = "$($DestinationPath)\ACL-Export-Errors-$($tsCustom).log"
$deniedPath = "$($DestinationPath)\ACL-Export-Denied-$($tsCustom).log"

# Create or append to the log file
$LogStream = [System.IO.File]::AppendText($LogPath)
$LogStream.WriteLine((Get-Date).ToString() + " - Starting script")

# Create or append to the error log file
$ErrorStream = [System.IO.File]::AppendText($ErrorPath)

# Prepare the CSV file for ACL
$ExportStream = New-Object -TypeName System.IO.StreamWriter -ArgumentList $ExportPath
$ExportStream.WriteLine("Folder,User or Group,Permissions,Inherited,Inheritance Flags,Propagation Flags")

# Prepare the CSV file for denied folders list
$DeniedStream = New-Object -TypeName System.IO.StreamWriter -ArgumentList $DeniedPath
$DeniedStream.WriteLine("Folder,Error")

# test if $TargetPath is accessible
if (![System.IO.Directory]::Exists($TargetPath)) {
    $ErrorStream.WriteLine((Get-Date).ToString() + " - Target path is not accessible")
    $ErrorStream.WriteLine((Get-Date).ToString() + " - $($TargetPath)")
    $ErrorStream.WriteLine((Get-Date).ToString() + " - Exiting")
    Write-Error "[NO_ACCESS] Could not access target $($TargetPath) - please check your permissions"

    if ( $ExportStream ) { $ExportStream.Close() }
    if ( $LogStream ) { $LogStream.Close() }
    if ( $ErrorStream ) { $ErrorStream.Close() }
    if ( $DeniedStream ) { $DeniedStream.Close() }

    Exit 1
}

# Create a DirectoryInfo object for the folder
$folder = New-Object System.IO.DirectoryInfo -ArgumentList (Convert-Path -LiteralPath $TargetPath)
$totalFolders = 0

# Function to iterate through subfolders and check access
function Export-FolderACL($folder) {
    
    try {
        $subfolders = $folder.GetDirectories()
        
        foreach ($subfolder in $subfolders) {
            $dirTL = 0
            try {
                $null = $subfolder.GetFiles()
                $dirTL = 1
                $LogStream.WriteLine((Get-Date).ToString() + " - Processing folder " + $subfolder.FullName)
                $script:totalFolders++

                # Attempt to get the folder's ACL information
                $ACLs = $null 
                try {
                    $ACLs = (Get-Acl -LiteralPath $subfolder.FullName).Access
                }
                catch {
                    # Log access error
                    Write-Warning (Get-Date).ToString() + "Could not get ACL for folder " + $subfolder.FullName
                    $ErrorStream.WriteLine((Get-Date).ToString() + " - [ERROR:79] " + $_.Exception.Message)
                    continue
                }

                # will fix this later
                if ( !$ACLs ) {
                    # try again, but with LiteralPath
                    $ACLs = (Get-Acl -LiteralPath $subfolder.FullName).Access
                }


                if ( !$ACLs ) {
                    $cmsg = If (![System.IO.Directory]::Exists($subfolder.FullName)) {"FOLDER_EXISTS"} Else {"FOLDER_NOT_FOUND"}
                    
                    $warnMessage = "$((Get-Date).ToString()) - ACL ERROR: $($cmsg) '$($subfolder.FullName)'"
                    $ErrorStream.WriteLine($warnMessage)
                    Write-Warning $warnMessage
                    continue
                }
                
                # Loop through each ACL entry
                foreach ($ACL in $ACLs) {
                    # Skip any access rules for the NT AUTHORITY or BUILTIN groups
                    if ($ACL.IdentityReference.Value.StartsWith("NT AUTHORITY\") -or $ACL.IdentityReference.Value.StartsWith("BUILTIN\") -or $ACL.IdentityReference.Value.Equals("Everyone") -or $ACL.IdentityReference.Value.Equals("CREATOR OWNER")) {
                        continue
                    }

                    # Convert inheritance flags to human-readable format
                    $InheritanceFlags = switch ($ACL.InheritanceFlags) {
                        'None' {''}
                        'ObjectInherit' {'OI'}
                        'ContainerInherit' {'CI'}
                        'ContainerInherit, ObjectInherit' {'CI, OI'}
                        default {$ACL.InheritanceFlags}
                    }

                    # Convert propagation flags to human-readable format
                    $PropagationFlags = switch ($ACL.PropagationFlags) {
                        'None' {''}
                        'InheritOnly' {'IO'}
                        'NoPropagateInherit' {'NP'}
                        'NoPropagateInherit, InheritOnly' {'NP, IO'}
                        default {$ACL.PropagationFlags}
                    }

                    # Write ACL information to CSV file
                    $Line = '"' + $subfolder.FullName + '","' + $ACL.IdentityReference + '",' + $ACL.FileSystemRights + ',' + $ACL.IsInherited + ',"' + $InheritanceFlags + '","' + $PropagationFlags + '"'
                    $ExportStream.WriteLine($Line)
                }
                
            } 
            catch [System.UnauthorizedAccessException] {
                Write-Warning "[WARNING][UNAUTHORIZED] $($subfolder.FullName)"
                $DeniedStream.WriteLine("`"$($subfolder.FullName)`",`"Unauthorized`"")
                $ErrorStream.WriteLine((Get-Date).ToString() + " - [ERROR:79] $($subfolder.FullName)" + $_.Exception.Message)
            }
            catch [System.IO.PathTooLongException] {
                Write-Warning "[WARNING][TOOLONG] $($subfolder.FullName)"
                $DeniedStream.WriteLine("`"$($subfolder.FullName)`",`"LongPath`"")
                $ErrorStream.WriteLine((Get-Date).ToString() + " - [ERROR:80] $($subfolder.FullName)" + $_.Exception.Message) 
            }
            catch [System.IO.DirectoryNotFoundException] {
                Write-Warning "[WARNING][NOTFOUND] $($subfolder.FullName)"
                $DeniedStream.WriteLine("`"$($subfolder.FullName)`",`"NotFound`"")
                $ErrorStream.WriteLine((Get-Date).ToString() + " - [ERROR:81] $($subfolder.FullName)" + $_.Exception.Message)    
            }
            catch {
                Write-Warning "[WARNING][OTHER] $($subfolder.FullName)"
                $DeniedStream.WriteLine("`"$($subfolder.FullName)`",`"OtherEx`"")
                $ErrorStream.WriteLine((Get-Date).ToString() + " - [ERROR:82] $($subfolder.FullName)" + $_.Exception.Message)
            }
            
            # Recursively process subfolders
            # only if we have access to the curent subfolder
            if ( $dirTL -eq 1 ) {
                Export-FolderACL($subfolder)
            } 
        }
    } catch {
        Write-Error $_.Exception.Message
    }
}

# Call the function to process subfolders
Export-FolderACL($folder)

Write-Output " "
Write-Output "* DONE"

$StopWatch.Stop()
Write-Host "* Execution time: $($StopWatch.Elapsed)"
Write-Output "* $($totalFolders) folders"

# Log success
$LogStream.WriteLine((Get-Date).ToString() + " - Script completed successfully")
$LogStream.WriteLine((Get-Date).ToString() + " - Execution time: $($StopWatch.Elapsed)")

# close the streams
if ( $ExportStream ) { $ExportStream.Close() }
if ( $LogStream ) { $LogStream.Close() }
if ( $ErrorStream ) { $ErrorStream.Close() }
if ( $DeniedStream ) { $DeniedStream.Close() }