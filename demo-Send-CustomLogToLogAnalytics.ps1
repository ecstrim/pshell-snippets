<#

Table name: FOO_CL

Table schema:
{
	"TimeGenerated": "Datetime",
	"RAW": "ciao"
}	

#>

Add-Type -AssemblyName System.Web

$tenantId = ""; #the tenant ID in which the Data Collection Endpoint resides
$appId = ""; #the app ID created and granted permissions
$appSecret = ""; #the secret created for the above app - never store your secrets in the source code
$DcrImmutableId = ""
$DceURI = ""
$Table = "FOO_CL"
 
$log_entry = @{
    # Define the structure of log entry, as it will be sent
    TimeGenerated = Get-Date ([datetime]::UtcNow) -Format O
    RAW           = "Lorem ipsum dolor sit amet 2"
}

## Obtain a bearer token used to authenticate against the data collection endpoint
$scope = [System.Web.HttpUtility]::UrlEncode("https://monitor.azure.com//.default")   
$body = "client_id=$appId&scope=$scope&client_secret=$appSecret&grant_type=client_credentials"
$headers = @{"Content-Type" = "application/x-www-form-urlencoded" }
$uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$bearerToken = (Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers).access_token

# Sending the data to Log Analytics via the DCR!
$body = $log_entry | ConvertTo-Json -AsArray
$headers = @{"Authorization" = "Bearer $bearerToken"; "Content-Type" = "application/json" }
$uri = "$DceURI/dataCollectionRules/$DcrImmutableId/streams/Custom-$Table" + "?api-version=2021-11-01-preview"
$uploadResponse = Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers

# Let's see how the response looks
Write-Output $uploadResponse