<#

Exports the NTFS permissions for given target path

It uses .NET libraries wherever possible to minimize memory consumption
The usual powershell cmdlets where too slow and too memory hungry


usage:

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
$ErrorStream.WriteLine((Get-Date).ToString() + " - Starting script")

# test if $TargetPath is accessible
if (![System.IO.Directory]::Exists($Path)) {
    $ErrorStream.WriteLine((Get-Date).ToString() + " - Target path is not accessible")
    $ErrorStream.WriteLine((Get-Date).ToString() + " - $($TargetPath)")
    $ErrorStream.WriteLine((Get-Date).ToString() + " - Exiting")
}


try {
    # Get all subdirectories recursively
    $Folders = [System.IO.Directory]::EnumerateDirectories($TargetPath, "*", [System.IO.SearchOption]::AllDirectories)

    # Create CSV file and write header row
    $ExportStream = New-Object -TypeName System.IO.StreamWriter -ArgumentList $ExportPath
    $ExportStream.WriteLine("Folder,User or Group,Permissions,Inherited,Inheritance Flags,Propagation Flags")

    # Loop through each folder and get ACL information
    foreach ($Folder in $Folders) {
        $LogStream.WriteLine((Get-Date).ToString() + " - Processing folder " + $Folder)

        # Attempt to get the folder's ACL information
        try {
            $ACLs = (Get-Acl $Folder).Access
        }
        catch {
            # Log access error
            $ErrorStream.WriteLine((Get-Date).ToString() + " - ERROR: " + $_.Exception.Message)
            continue
        }

        if ( !$ACLs ) {
            $ErrorStream.WriteLine((Get-Date).ToString() + " - ACCESS ERROR: " + $Folder)
            continue
        }

        # Loop through each ACL entry
        foreach ($ACL in $ACLs) {
            # Skip any access rules for the NT AUTHORITY or BUILTIN groups
            if ($ACL.IdentityReference.Value.StartsWith("NT AUTHORITY\") -or $ACL.IdentityReference.Value.StartsWith("BUILTIN\") -or $ACL.IdentityReference.Value.Equals("Everyone")) {
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
    }

    # Close the CSV file
    $ExportStream.Close()

    # Log success
    $LogStream.WriteLine((Get-Date).ToString() + " - Script completed successfully")
}
catch {
    # Log error
    $LogStream.WriteLine((Get-Date).ToString() + " - ERROR: " + $_.Exception.Message)
}
finally {
    # Close the log files
    $LogStream.Close()
    $ErrorStream.Close()
}
