<#
.Synopsis
Run this only after you understand what it does!

.Description
Generates a list of Active Directory users, last logon date, password last set, password never expires
If not provided, it gets the members of Domain Admins group

.Parameter GroupName
Group name to get the users from

.Parameter Export 
Provide a path for the exported CSV file

.Parameter Display
Display the list at the end

.Parameter Silent
Do not display the progress bar and the messages. Use it when run as job


#>

Param (
    [Parameter(Mandatory = $false)][String]$GroupName = "Domain Admins",
    [Parameter(Mandatory = $false)][String]$Export,
    [Parameter(Mandatory = $false)][Switch]$Display,
    [Parameter(Mandatory = $false)][Switch]$Silent
)

Import-Module ActiveDirectory

if ($Silent -ne $null) { Write-Host " " }

if ($Export -ne $false) {
    if ($Silent -ne $null) { 
        Write-Host "* Export Requested"
        Write-Host "Destination path [$Export]"
    }

    $expTest = Test-Path -Path $Export
    if (!$expTest) {
        Write-Error "Provided export path is not accessible!"
        Write-Error $Export
        Exit 200
    }
    $trimmedPath = $Export.TrimEnd('\')
    $destinationFile = "$($trimmedPath)\Admins-NoPwdExpiry-$(get-date -f yyyy-MM-dd).csv"
}

# Get the list of users in the Domain Admins group
if ($Silent -ne $null) { Write-Host "* Fetching users  in group $($GroupName)" }
$allUsers = Get-ADGroupMember -Identity $GroupName

# Initialize an empty array to store the results
$results = @()
# Need these for the progress bar
$progressCounter = 0
$totalCount = $allUsers.count


# Loop through each user in the Domain Admins group
foreach ($user in $allUsers) {
    $progressCounter++
    if ($Silent -ne $null) { 
        Write-Progress -Activity 'Processing Users' -Status "Scanned: $progressCounter of $totalCount" -CurrentOperation $user.Name -PercentComplete(($progressCounter / $totalCount) * 100)
    }
	
    # Get the user object
    $userObject = Get-ADUser -Identity $user -Properties * | Select-Object Name, Enabled, LastLogonDate, @{Name = 'PwdLastSet'; Expression = { [DateTime]::FromFileTime($_.PwdLastSet) } }, PasswordNeverExpires

    # Create a custom object to store the user's name and group membership
    $obj = [PSCustomObject]@{
        Name                 = $userObject.Name
        Enabled              = $userObject.Enabled
        LastLogonDate        = $userObject.LastLogonDate
        PwdLastSet           = $userObject.PwdLastSet
        PasswordNeverExpires = $userObject.PasswordNeverExpires
    }

    # Add the object to the results array
    $results += $obj
}

# Export the results to a CSV file
#
if ($Export -ne $false) {
    $results | Export-Csv -Path $destinationFile -NoTypeInformation -Encoding UTF8 -Delimiter ","
}

# Output result to console
if ($Display -eq $true) {
    $results | Format-List 
} 
