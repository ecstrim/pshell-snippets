# RemoveAllMembersFromSchemaAdmins.ps1

# Ensure the Active Directory module is imported
if (-not (Get-Module -Name ActiveDirectory)) {
    Import-Module ActiveDirectory
}

# Get the Schema Admins group
$SchemaAdminsGroup = Get-ADGroup -Identity "Schema Admins"

# Get the members of the Schema Admins group
$SchemaAdminsMembers = Get-ADGroupMember -Identity $SchemaAdminsGroup -Recursive

# Remove each member from the Schema Admins group
foreach ($member in $SchemaAdminsMembers) {
    Remove-ADGroupMember -Identity $SchemaAdminsGroup -Member $member -Confirm:$false
}

Write-Host "All members have been removed from the Schema Admins group."
