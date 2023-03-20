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
.NOTES
  Version:        1.0
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



$eDT = Get-Date
$tsCustom = [STRING]$eDT.Year + "-" + $("{0:D2}" -f $eDT.Month) + "-" + $("{0:D2}" -f $eDT.Day) + "_" + $("{0:D2}" -f $eDT.Hour) + "." + $("{0:D2}" -f $eDT.Minute) + "." + $("{0:D2}" -f $eDT.Second)

$ExportPath = "$($DestinationPath)\ACL-Export-$($tsCustom).csv"
$LogPath    = "$($DestinationPath)\ACL-Export-Log-$($tsCustom).log"
$ErrorPath  = "$($DestinationPath)\ACL-Export-Errors-$($tsCustom).log"

# Create or append to the log file
$LogStream = [System.IO.File]::AppendText($LogPath)
$LogStream.WriteLine((Get-Date).ToString() + " - Starting script")

# Create or append to the error log file
$ErrorStream = [System.IO.File]::AppendText($ErrorPath)

# test if $TargetPath is accessible
if (![System.IO.Directory]::Exists($TargetPath)) {
    $ErrorStream.WriteLine((Get-Date).ToString() + " - Target path is not accessible")
    $ErrorStream.WriteLine((Get-Date).ToString() + " - $($TargetPath)")
    $ErrorStream.WriteLine((Get-Date).ToString() + " - Exiting")
    Write-Error "[NO_ACCESS] Could not access target $($TargetPath) - please check your permissions"
    Exit 1
}

try {
    # Get all subdirectories recursively
    $Folders = [System.IO.Directory]::EnumerateDirectories($TargetPath, "*", [System.IO.SearchOption]::AllDirectories)
    # Create CSV file and write header row
    $ExportStream = New-Object -TypeName System.IO.StreamWriter -ArgumentList $ExportPath
    $ExportStream.WriteLine("Folder,User or Group,Permissions,Inherited,Inheritance Flags,Propagation Flags")

    # Loop through each folder and get ACL information
    $i = 0
    foreach ($Folder in $Folders) {
        $LogStream.WriteLine((Get-Date).ToString() + " - Processing folder " + $Folder)

        # Attempt to get the folder's ACL information
        try {
            $ACLs = (Get-Acl $Folder).Access
        }
        catch {
            # Log access error
            Write-Warning (Get-Date).ToString() + "Could not get ACL for folder " + $Folder
            $ErrorStream.WriteLine((Get-Date).ToString() + " - [ERROR:79] " + $_.Exception.Message)
            continue
        }

        if ( !$ACLs ) {
            $cmsg = If (![System.IO.Directory]::Exists($Folder)) {"FOLDER_EXISTS"} Else {"FOLDER_NOT_FOUND"}
            
            $warnMessage = (Get-Date).ToString() + " - ACL ERROR: " + $cmsg + " '" + $Folder + "'"
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
            $Line = '"' + $Folder + '","' + $ACL.IdentityReference + '",' + $ACL.FileSystemRights + ',' + $ACL.IsInherited + ',"' + $InheritanceFlags + '","' + $PropagationFlags + '"'
            $ExportStream.WriteLine($Line)
        }
        $i++
    }

    # Close the CSV file
    $ExportStream.Close()

    # Log success
    $LogStream.WriteLine((Get-Date).ToString() + " - ")
    $LogStream.WriteLine((Get-Date).ToString() + " - Processed $($i) folders")
    $LogStream.WriteLine((Get-Date).ToString() + " - Script completed successfully")
}
catch {
    # Log error
    $errorMessage = (Get-Date).ToString() + " - [ERROR:143] " + $_.Exception.Message
    $LogStream.WriteLine($errorMessage)
    $ErrorStream.WriteLine($errorMessage)
    Write-Warning $errorMessage
    Write-Error "[FATAL ERROR] Could not access folder"

    $LogStream.Close()
    $ErrorStream.Close()
    $ExportStream.Close()


    exit 2
}
finally {
    # Close the log files
    $LogStream.Close()
    $ErrorStream.Close()
}
