<#
    
    This script retrieves Azure Active Directory Sign-in logs for privileged users from the Microsoft Graph API and send an email report.
    Only the sign-ins for the last day will be retrieved (that can be modified with $startDate $endDate).

    See the official documentation for more info on the Audit logs API:
    https://developer.microsoft.com/en-us/graph/docs/api-reference/beta/resources/signin

    To connect to the Microsoft Graph API you need to provide ClientId, ClientSecret and TenantDomain.

    See the official documentation for more info on how to add an app to Azure AD and grant API access:
    https://docs.microsoft.com/en-us/azure/active-directory/identity-protection/graph-get-started#create-a-new-app-registration
    
    The email report is sent via Microsoft Flow with an HTTP request trigger. You have to provide the HTTP POST URL.
    More info on how to create such Flow:
    https://medium.com/@zaab_it/microsoft-flow-send-email-from-http-request-f6577ad46b2c

#>

$ClientID = $env:ClientID
$ClientSecret = $env:ClientSecret
$TenantDomain = $env:TenantDomain
$loginURL = "https://login.microsoft.com"
$resource = "https://graph.microsoft.com"

$uriFlowEmail = $env:uriFlowEmail

# Email style
$style = "<style>"
$style += "BODY{background-color:white; font-family: Arial, Sans-Serif; font-size: 10pt; color: black;}"
$style += "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
$style += "TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color: #999999; color: white; font-size: 11pt;}"
$style += "TD{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color: white; color: black; font-size: 10pt;}"
$style += "</style>"

# Email variables
$emailRecipient = $env:EmailRecipient
$emailSubject = "AAD Privileged Users Sign-ins Report $(Get-Date -Format yyyy/MM/dd)"

# Email Body header
$emailBodyHeader = "<h1>Azure AD - Office 365 Privileged Users Access Report</h1>"
$emailBodyHeader += "<p>To review sign-ins activity go to: <a href='https://portal.azure.com/#blade/Microsoft_AAD_IAM/UsersManagementMenuBlade/SignIns' target='_blank'>Azure Active Directory Portal Sign-ins</a></p>"
$emailBodyHeader += "<p>Date: $(Get-Date)</p>"
$emailBodyHeader += "<p>Tenant: $($TenantDomain)</p>"


# Set empty global variables
$global:headerParams = @{}
$global:tokenExpiresOn = $null

function Set-AuthHeader {
    
    $body = @{grant_type = "client_credentials"; resource = $resource; client_id = $ClientID; client_secret = $ClientSecret }
    $oauth = Invoke-RestMethod -Method Post -Uri $loginURL/$TenantDomain/oauth2/token?api-version=1.0 -Body $body
    if ($oauth.access_token) { 
        Write-Output "Success: auth token retrieved"
        $global:tokenExpiresOn = $oauth.expires_on
        $global:headerParams = @{'Authorization' = "$($oauth.token_type) $($oauth.access_token)" }
    }
    else {
        Write-Output "Error: auth token not retrieved"
    }
    
}

function Get-OrganizationInfo {

    if ($tokenExpiresOn -le [Math]::Floor((Get-Date ([datetime]::UtcNow) -UFormat %s))) { Set-AuthHeader }
    [uri]$uriOrganizationInfo = "https://graph.microsoft.com/v1.0/organization"
    $resOrganizationInfo = Invoke-RestMethod -Method Get -Uri $uriOrganizationInfo.AbsoluteUri -Headers $headerParams
    $resOrganizationInfo.value

}

function Get-DirectoryRoles {

    if ($tokenExpiresOn -le [Math]::Floor((Get-Date ([datetime]::UtcNow) -UFormat %s))) { Set-AuthHeader }
    [uri]$uriDirectoryRoles = "https://graph.microsoft.com/v1.0/directoryRoles"
    $resDirectoryRoles = Invoke-RestMethod -Method Get -Uri $uriDirectoryRoles.AbsoluteUri -Headers $headerParams
    $resDirectoryRoles.value

}

function Get-RoleMember {
    [cmdletbinding()]
    Param (
        [string]$roleId
    )

    if ($tokenExpiresOn -le [Math]::Floor((Get-Date ([datetime]::UtcNow) -UFormat %s))) { Set-AuthHeader }
    [uri]$uriRoleMembers = "https://graph.microsoft.com/v1.0/directoryRoles/$($roleId)/members"
    $resRoleMembers = Invoke-RestMethod -Method Get -Uri $uriRoleMembers.AbsoluteUri -Headers $headerParams
    $resRoleMembers.value

}

function Get-Signins {
    [cmdletbinding()]
    Param (
        [string]$userId,
        [string]$startDate,
        [string]$endDate
    )

    if ($tokenExpiresOn -le [Math]::Floor((Get-Date ([datetime]::UtcNow) -UFormat %s))) { Set-AuthHeader }
    [uri]$uriSignins = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=userId eq '$($userId)' and createdDateTime ge $($startDate) and createdDateTime le $($endDate)"
    $resSignins = Invoke-RestMethod -Method Get -Uri $uriSignins.AbsoluteUri -Headers $headerParams
    $resSignins.value

}

# Initiate the Authentication header
Set-AuthHeader

if ($headerParams["Authorization"]) {

    $OrganizationInfo = Get-OrganizationInfo
    $emailBodyHeader += "<p>Organization: $($OrganizationInfo.displayName)</p>"

    $directoryRoles = Get-DirectoryRoles
    $adminDirectoryRoles = $directoryRoles | Where-Object { $_.displayName -match "Administrator" }

    $members = @()

    # Get all privileged users in each role
    foreach ($adminDirectoryRole in $adminDirectoryRoles) {

        $members += Get-RoleMember -roleId $adminDirectoryRole.id

    }

    # Keep all unique privileged users
    $admins = $members | Sort-Object -Property userPrincipalName -Unique

    $allusersReportHtml = ""
    $allusersReportHtml += "<p>--------------------------------------------------</p>"
    $allusersReportHtml += "<p>All privileged users:</p>"
    $allusersReportHtml += $admins | ConvertTo-Html -Fragment -Property displayName

    # Set start and end date for filtering
    $now = (Get-Date).ToUniversalTime()
    $previousDay = $now.AddDays(-1)
    $startDate = $previousDay.Date.ToString("o")
    $endDate = $now.Date.ToString("o")

    $allusersReportHtml += "<p>Sign-ins from: $startDate to $endDate</p>"

    foreach ($admin in $admins) {

        $signins = Get-Signins -userId $admin.id -startDate $startDate -endDate $endDate

        $signinsCount = $signins.Count
        $ips = $signins | Select-Object -Property ipAddress | Sort-Object -Property ipAddress -Unique
        $apps = $signins | Select-Object -Property appDisplayName | Sort-Object -Property appDisplayName -Unique
        $clientApps = $signins | Select-Object -Property clientAppUsed | Sort-Object -Property clientAppUsed -Unique
        $hasRisky = @($signins | Where-Object -Property "isRisky" -EQ $true).Count
        $signinsErrorsCount = @($signins | Select-Object -ExpandProperty Status | Where-Object -Property errorCode -NE 0).Count
        $signinsErrors = $signins | Select-Object -ExpandProperty Status | Where-Object -Property errorCode -NE 0 | Sort-Object -Property errorCode -Unique | Select-Object -Property errorCode, failureReason
        $signinsDevices = $signins | Select-Object -ExpandProperty deviceDetail | Sort-Object -Property deviceId, displayName, operatingSystem, browser -Unique
        $signinsLocations = $signins | Select-Object -ExpandProperty location | Select-Object -Property countryOrRegion, city | Sort-Object -Property countryOrRegion, city -Unique
        $signinsCaps = $signins | Select-Object -ExpandProperty appliedConditionalAccessPolicies | Where-Object -Property result -NE "notApplied" | Select-Object -Property displayName, @{N = "enforcedGrantControls"; E = { $_.enforcedGrantControls -join "; " } }, result | Sort-Object -Property displayName, enforcedGrantControls, result -Unique

        $userReportHtml = "<p>--------------------------------------------------</p>"
        $userReportHtml += "<p><b>User:</b> $($admin.userPrincipalName)</p>"
        $userReportHtml += "<p><b>Total number of sign-ins:</b> $($signinsCount)</p>"
    
        if ($signinsCount -gt 0) {
    
            $userReportHtml += "<p><b>Risky sign-ins count:</b> $($hasRisky)</p>"
            $userReportHtml += "<p><b>Error sign-ins count:</b> $($signinsErrorsCount)</p>"
            $userReportHtml += "<p><b>Errors:</b></p>"
            $userReportHtml += $signinsErrors | ConvertTo-Html -Fragment
            $userReportHtml += "<p><b>Conditional Access Policies:</b></p>"
            $userReportHtml += $signinsCaps | ConvertTo-Html -Fragment
            $userReportHtml += "<p><b>IP:</b></p>"
            $userReportHtml += $ips | ConvertTo-Html -Fragment -Property ipAddress
            $userReportHtml += "<p><b>Locations list:</b></p>"
            $userReportHtml += $signinsLocations | ConvertTo-Html -Fragment
            $userReportHtml += "<p><b>Apps:</b></p>"
            $userReportHtml += $apps | ConvertTo-Html -Fragment -Property appDisplayName
            $userReportHtml += "<p><b>Client apps:</b></p>"
            $userReportHtml += $clientApps | ConvertTo-Html -Fragment -Property clientAppUsed
            $userReportHtml += "<p><b>Devices list:</b></p>"
            $userReportHtml += $signinsDevices | ConvertTo-Html -Fragment

        }

        $allusersReportHtml += $userReportHtml

    }

    $emailBody = $style + $emailBodyHeader + $allusersReportHtml + "<p>&nbsp;</p>"

    $bodyFlowEmail = @{
        "subject" = $emailSubject
        "body"    = $emailBody
        "to"      = $emailRecipient
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Method Post -Uri $uriFlowEmail -Body $bodyFlowEmail -ContentType "application/json"
    }
    catch {
        Write-Output "Error: Request to Flow Email failed"
    }

}
else { Write-Output "Error: header authorization empty" }