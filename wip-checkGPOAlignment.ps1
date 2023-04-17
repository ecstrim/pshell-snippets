## powershell description block
<#
.SYNOPSIS
    Script to check the Group Policy Object alignment between the source and target domain controllers.
.DESCRIPTION
    This script will check the Group Policy Object alignment between the source and target domain controllers.
.PARAMETER SourceDomainController
    The source domain controller to check.
.PARAMETER TargetDomainController
    The target domain controller to check.
.PARAMETER GroupPolicyObject
    The Group Policy Object to check.
.EXAMPLE
    .\wip-checkGPOAlignment.ps1 -SourceDomainController "DC1" -TargetDomainController "DC2" -GroupPolicyObject "GPO1"
.NOTES

#>
# Import required .NET libraries
Add-Type -AssemblyName "System.IO" 

function Write-Log {
    <# Usage example:
    # Write-Log "This is an informational message."
    # Write-Log "This is a warning message." "Warning"
    # Write-Log "This is an error message." "Error"
    # Write-Log "This is a success message." "Success"
    # Write-Log "This is an informational message." "Info" "C:\Temp\checkGPOAlignment.log"
    #>
    param (
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")][string]$Level = "Info",

        # Optional parameters
        [string]$LogFilePath = "$PSScriptRoot\checkGPOAlignment.log"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"

    # Add log entry to file
    # Add-Content -Path $logFile -Value $logEntry
    [System.IO.File]::AppendAllText($LogFilePath, $logEntry + [Environment]::NewLine)

    switch ($Level) {
        "Info" { Write-Host -ForegroundColor White   $logEntry }
        "Warning" { Write-Host -ForegroundColor Yellow  $logEntry }
        "Error" { Write-Host -ForegroundColor Red     $logEntry }
        "Success" { Write-Host -ForegroundColor Green  $logEntry }
    }
}


function Write-Message {
    <# Usage example:
    # Write-Message "This is an informational message."
    # Write-Message "This is a warning message." "Warning"
    # Write-Message "This is an error message." "Error"
    # Write-Message "This is a success message." "Success"
    #>
    param (
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")][string]$Level = "Info",
        [string]$Log="NoLog"
    )

    switch ($Level) {
        "Info" { Write-Host -ForegroundColor White   $Message }
        "Warning" { Write-Host -ForegroundColor Yellow  $Message }
        "Error" { Write-Host -ForegroundColor Red     $Message }
        "Success" { Write-Host -ForegroundColor Green  $Message }
    }

    # check if logging is requested
    if ($Log -eq "Log") {
        Write-Log -Message $Message -Level $Level
    }
}


# get gpo list from specified dc
function Get-GPOList {
    param (
        [string]$DomainController,
        [switch]$Verbose
    )
    
    # check if verbose logging is requested
    if ($Verbose) {
        Write-Message -Message "Getting GPO list from $DomainController" -Level "Info" -Log "Log"
    }

    # get gpo list from specified dc
    $gpoList = Get-GPO -DomainController $DomainController

    # if verbose then show gpo count
    if ($Verbose) {
        Write-Message -Message "Found $($gpoList.Count) GPOs on $DomainController" -Level "Info" -Log "Log"
    }

    # return gpo list
    return $gpoList
}


## get the list of dc's in the domain
$dcList = Get-ADDomainController -DomainController $DomainController -Filter * -Properties *

## find the pdc holder
$pdcHolder = $dcList | Where-Object { $_.IsPdcRoleOwner -eq $true }

## get the gpo list from the pdc holder
$pdcGPOS = Get-GPOList -DomainController $pdcHolder.Name -Verbose

## create a new list of objects to store gpos
$pdc_polList = New-Object Collections.Generic.List[Object]

## check that all pdc gpos exist in sysvol path
## if a gpo doesn't exist in sysvol, mark it as not found
foreach ($gpo in $pdcGPOS) {
    ## get the gpo path
    $gpoPath = Get-GPO -Identity $gpo.Id -DomainController $pdcHolder.Name | Select-Object -ExpandProperty "Path"

    ## check if the gpo path exists
    ## if it doesn't, mark it as such
    ## add it anyway to the $pcd_polList
    if (Test-Path -Path $gpoPath) {
        $pdc_polList.Add([PSCustomObject]@{
            Name = $gpo.DisplayName
            ID = $gpo.Id
            Path = $gpoPath
            Found = $true
        })
    } else {
        $pdc_polList.Add([PSCustomObject]@{
            Name = $gpo.DisplayName
            ID = $gpo.Id
            Path = $gpoPath
            Found = $false
        })
    }
}

## now check the same for every other dc
foreach ($dc in $dcList) {
    ## get the gpo list from the dc
    $dcGPOS = Get-GPOList -DomainController $dc.Name -Verbose

    ## create a new list of objects to store gpos
    $dc_polList = New-Object Collections.Generic.List[Object]

    ## check that all dc gpos exist in sysvol path
    ## if a gpo doesn't exist in sysvol, mark it as not found
    foreach ($gpo in $dcGPOS) {
        ## get the gpo path
        $gpoPath = Get-GPO -Identity $gpo.Id -DomainController $dc.Name | Select-Object -ExpandProperty "Path"

        ## check if the gpo path exists
        ## if it doesn't, mark it as such
        ## add it anyway to the $pcd_polList
        if (Test-Path -Path $gpoPath) {
            $dc_polList.Add([PSCustomObject]@{
                Name = $gpo.DisplayName
                ID = $gpo.Id
                Path = $gpoPath
                Found = $true
            })
        } else {
            $dc_polList.Add([PSCustomObject]@{
                Name = $gpo.DisplayName
                ID = $gpo.Id
                Path = $gpoPath
                Found = $false
            })
        }
    }

    ## compare the gpo lists
    ## if the gpo is not found in the dc, mark it as not found
    foreach ($gpo in $pdc_polList) {
        ## check if the gpo is found in the dc
        ## if it isn't, mark it as such
        if ($dc_polList | Where-Object { $_.ID -eq $gpo.ID } | Select-Object -ExpandProperty "Found") {
            $gpo | Add-Member -MemberType NoteProperty -Name "Found" -Value $true
        } else {
            $gpo | Add-Member -MemberType NoteProperty -Name "Found" -Value $false
        }
    }
}