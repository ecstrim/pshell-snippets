# Get-ADUsers-Admins.ps1
# Import the Active Directory module
Import-Module ActiveDirectory

# Get the list of users in the Domain Admins group
$allUsers = Get-ADGroupMember -Identity "Domain Admins"

# Initialize an empty array to store the results
$results = @()
# Need these for the progress bar
$progressCounter = 0
$totalCount = $allUsers.count


# Loop through each user in the Domain Admins group
foreach ($user in $allUsers) {
    $progressCounter++
    Write-Progress -Activity 'Processing Users' -Status "Scanned: $progressCounter of $totalCount" -CurrentOperation $user.Name -PercentComplete(($progressCounter / $totalCount) * 100)
	
    # Get the user object
    $userObject = Get-ADUser -Identity $user

    # Get the list of groups the user is a member of
    $groups = Get-ADPrincipalGroupMembership -Identity $user | Select-Object -ExpandProperty Name
    if ( $groups -like "*dmin*" ) {
        $groupsFoo = 'YES'
    }
    else {
        $groupsFoo = 'no'
    }
    # Create a custom object to store the user's name and group membership
    $obj = [PSCustomObject]@{
        Name                 = $userObject.Name
        Enabled              = $userObject.Enabled
        LastLogonDate        = $userObject.LastLogonDate
        PwdLastSet           = $userObject.PwdLastSet
        PasswordNeverExpires = $userObject.PasswordNeverExpires
        Groups               = $groups
        AdminGroup           = $groupsFoo
    }
    

    # Add the object to the results array
    $results += $obj
}

# Export the results to a CSV file
# $results | Export-Csv -Path .\ADUsers-Groups-$(get-date -f yyyy-MM-dd).csv -NoTypeInformation -Encoding UTF8 -Delimiter ","

# Output result to console
$results | Format-List 
