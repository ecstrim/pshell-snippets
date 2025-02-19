$resourceGroupName = "rg-xxx-xxxx"

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

$today = Get-Date
if ($today.DayOfWeek -eq 'Saturday' -or $today.DayOfWeek -eq 'Sunday') {
    exit 0
}
else {
    $vms = Get-AzVM -ResourceGroupName $resourceGroupName
    $vms | Select-Object Name | % { Start-AzVM -Name $_.Name -ResourceGroupName $resourceGroupName -NoWait }
}
