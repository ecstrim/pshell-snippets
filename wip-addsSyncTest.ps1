<#
.SYNOPSIS
  ADDS User & GPO Sync test
  This is a WIP! 
  Please do not use in Production
.DESCRIPTION
  Creates a temporary user and a temporary GPO on the PDC, then check every other DC to see when they are propagated
.NOTES
  Version:        0.1 BETA
  Author:         Mihai Olaru
  Creation Date:  2023-09
  Purpose/Change: Initial script development
  
#>

Import-Module ActiveDirectory
Import-Module GroupPolicy

$domainComponents = (Get-ADDomain).DistinguishedName -replace 'DC=', '' -split ',' | ForEach-Object { "DC=$_" }
$path = "OU=Users," + ($domainComponents -join ',')

# Variables for user creation
$newUser = @{
    SamAccountName  = "SyncTestUser"
    GivenName       = "SyncTest"
    Surname         = "User"
    Name            = "SyncTest User"
    AccountPassword = (ConvertTo-SecureString "Pa$$w0rd321" -AsPlainText -Force)
    Path            = $path
    Enabled         = $true
}

# Variables for GPO creation
$newGPO = @{
    Name = "SyncTestGPO"
}

# Get the primary domain controller
$pdc = (Get-ADDomainController -Discover -Service PrimaryDC)

# Create the user account on the PDC
New-ADUser @newUser -Server $pdc.HostName[0]

# Create the GPO on the PDC
New-GPO @newGPO -Server $pdc.HostName[0]

# Function to check propagation
function CheckPropagation($objectType, $objectName) {
    $dcList = Get-ADDomainController -Filter * | Where-Object { $_.HostName -ne $pdc.HostName[0] }
    $propagationResults = @()

    while ($dcList.Count -gt 0) {
        foreach ($dc in $dcList) {
            try {
                if ($objectType -eq "User") {
                    $object = Get-ADUser -Identity $objectName -Server $dc.HostName
                }
                elseif ($objectType -eq "GPO") {
                    $object = Get-GPO -Name $objectName -Server $dc.HostName
                }

                if ($null -ne $object) {
                    # Remove the DC from the list and store the propagation result
                    $dcList = $dcList | Where-Object { $_.HostName -ne $dc.HostName }
                    $propagationResults += [PSCustomObject]@{
                        ObjectType      = $objectType
                        ObjectName      = $objectName
                        DCName          = $dc.HostName
                        PropagationTime = (Get-Date)
                    }
                    Write-Host "$objectType $objectName synchronized on $($dc.HostName) at $(Get-Date)"
                }
            }
            catch {
                Write-Host "Waiting for $($dc.HostName) to synchronize $objectType $objectName..."
            }
        }
        Start-Sleep -Seconds 10
    }

    # Return the propagation results
    return $propagationResults
}

# Check propagation for user and GPO
$userPropagationResults = CheckPropagation "User" $newUser.SamAccountName
$gpoPropagationResults = CheckPropagation "GPO" $newGPO.Name

# Display the propagation results
$userPropagationResults + $gpoPropagationResults | Format-Table -AutoSize