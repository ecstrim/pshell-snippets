<#

Just a script to quickly create an OU and some users

#>

# Import the necessary module
Import-Module ActiveDirectory

# Fetch Domain Details
$domainDetails = Get-ADDomain
$domainController = $domainDetails.PDCEmulator
$ouPath = $domainDetails.DistinguishedName

# Specify OU Details
$ouName = "CORP_Users"

# Specify User Details
$users = @(
    @{Username="user1"; Password="Password123!"},
    @{Username="user2"; Password="Password123!"},
    @{Username="user3"; Password="Password123!"}
)

# Create OU
New-ADOrganizationalUnit -Name $ouName -Path $ouPath -Server $domainController

# Iterate through each user in $users
foreach ($user in $users) {
    # Create User
    New-ADUser -Name $user.Username `
        -GivenName $user.Username `
        -Surname "Hydrated" `
        -UserPrincipalName "$($user.Username)@$($domainDetails.DNSRoot)" `
        -SamAccountName $user.Username `
        -UserPassword (ConvertTo-SecureString -AsPlainText $user.Password -Force) `
        -Enabled $true `
        -Path "OU=$ouName,$ouPath" `
        -PassThru `
        -Server $domainController
}
