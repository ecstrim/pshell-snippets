$Events = Get-WinEvent -Oldest -MaxEvents 3 -FilterHashTable @{LogName = 'Security'; ID = 4771} `
            | Select-Object *, @{Name = 'ADUser'; Expression = {Get-ADUser -Identity $_.UserId.Value | Select-Object samaccountname, userprincipalname, DistinguishedName}} `
            | Select-Object Id, MachineName, TimeCreated, Message, `
            @{Name='Username';Expression={$_.ADUser.samaccountname}}, `
            @{Name='UPN';Expression={$_.ADUser.userprincipalname}}, `
            @{Name='DistinguishedName';Expression={$_.ADUser.DistinguishedName}}