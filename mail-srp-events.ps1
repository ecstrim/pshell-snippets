$EmailTo      = "you know what to put here"
$EmailFrom    = "you know what to put here"
$Subject      = "*** SRP REPORT ***" 
$SMTPServer   = "you know what to put here" 
$SMTPUsername = "you know what to put here"
$SMTPPassword = "you know what to put here"

function buildBodyItemTable($Item) {
    $BodyItem = @"
<table padding="1" spacing="1" style="">
    <tr><td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">EventID:</td> <td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">$($Item.Id)</td></tr>
    <tr><td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">TimeCreated:</td> <td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">$($Item.TimeCreated)</td></tr>
    <tr><td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">Computer:</td> <td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">$($Item.Computer)</td></tr>
    <tr><td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">Username:</td> <td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">$($Item.Username)</td></tr>
    <tr><td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">UPN:</td> <td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">$($Item.UPN)</td></tr>
    <tr><td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">DN:</td> <td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">$($Item.DistinguishedName)</td></tr>
    <tr><td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">Message:</td> <td style="background-color: #e6e6e6; padding: 5px 5px 5px 5px;">$($Item.Message)</td></tr>
</tr>
</table>

<div><hr size=\"1\"></div>

"@

    return $BodyItem
}

$Events = Get-WinEvent -Oldest -MaxEvents 3 -FilterHashTable @{LogName = 'Application'; ProviderName = 'Microsoft-Windows-SoftwareRestrictionPolicies'} `
            | Select-Object *, @{Name = 'ADUser'; Expression = {Get-ADUser -Identity $_.UserId.Value | Select-Object samaccountname, userprincipalname, DistinguishedName}} `
            | Select-Object Id, MachineName, TimeCreated, Message, `
            @{Name='Username';Expression={$_.ADUser.samaccountname}}, `
            @{Name='UPN';Expression={$_.ADUser.userprincipalname}}, `
            @{Name='DistinguishedName';Expression={$_.ADUser.DistinguishedName}}

$Items = @() 
$EmailBody = "<div>"
foreach ($Event in $Events) {
    $i = New-Object PSObject -Property ([Ordered] @{
        'Id' = $Event.Id 
        'Computer' = $Event.MachineName 
        'TimeCreated' = Get-Date -Date $Event.TimeCreated -format "yyyy-MM-dd HH:mm"
        'Username' = $Event.Username 
        'UPN' = $Event.UPN 
        'DistinguishedName' = $Event.DistinguishedName 
        'Message' = $Event.Message.TrimEnd('.')
	  })

    $Items += $i

    $EmailBody += buildBodyItemTable($i)
}
$EmailBody += "</div>"

$SMTPMessage = New-Object System.Net.Mail.MailMessage
$SMTPMessage.From       = ($EmailFrom) 
$SMTPMessage.To.Add($EmailTo) 
$SMTPMessage.Subject    = $Subject 
$SMTPMessage.IsBodyHTML = $true 
$SMTPMessage.Body       = $EmailBody
$SMTPClient             = New-Object Net.Mail.SmtpClient($SmtpServer, 587) 
$SMTPClient.EnableSsl   = $true 
$SMTPClient.Credentials = New-Object System.Net.NetworkCredential($SMTPUsername, $SMTPPassword); 
$SMTPClient.Send($SMTPMessage)
