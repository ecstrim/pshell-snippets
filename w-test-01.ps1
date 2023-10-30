# export the current security policy
secedit /export /cfg C:\temp\securitypolicy.cfg
# modify
(Get-Content -path C:\temp\securitypolicy.cfg) | Foreach-Object {$_ -replace "PasswordComplexity=1", "PasswordComplexity=0"} | Set-Content -Path C:\temp\securitypolicy.cfg
# apply
secedit /configure /db $env:windir\security\local.sdb /cfg C:\temp\securitypolicy.cfg /areas SECURITYPOLICY
