##Tilo Runbook quick hack. 

## add to Automation Account under Shared Resources "Default Automation Credential" which has access to start VMs
## Add to VM tag: MyAutoStartPrio with a number 


##Get account
$azureCredential = Get-AutomationPSCredential -Name "Default Automation Credential"
if($azureCredential -ne $null)
        {
		    Write-Output "$(Get-Date -format s) :: Attempting to authenticate as: [$($azureCredential.UserName)]"
        }
        else
        {
            throw "$(Get-Date -format s) :: No cred asset with name 'Default Automation Credential' was found. Specify a stored credential asset"
        }

## Connect: 
##Connect-AzureAD -Credential $azureCredential
Login-AzureRmAccount -Credential $azureCredential

##:List all subs which are enabled
#$AllSubID = (Get-AzureRmSubscription | Where {$_.State -eq "enabled"}).SubscriptionId
$AllSubID = (Get-AzureRmSubscription).SubscriptionId
Write-Output "$(Get-Date -format s) :: List of Subscription below"
$AllSubID

$AllVMList = @()
Foreach ($SubID in $AllSubID) {
Select-AzureRmSubscription -Subscriptionid "$SubID"

$VMs = Get-AzureRmVM | Where-Object { $_.tags.MyAutoStartPrio -ne $null }
Foreach ($VM in $VMs) {
	$VM = New-Object psobject -Property @{`
		"Subscriptionid" = $SubID;
		"ResourceGroupName" = $VM.ResourceGroupName;
		"MyAutoStartPrio" = $VM.tags.MyAutoStartPrio;
		"VMName" = $VM.Name}
		$AllVMList += $VM | select Subscriptionid,ResourceGroupName,VMName,MyAutoStartPrio
		}
}


$AllVMListSorted = $AllVMList | Sort-Object -Property MyAutoStartPrio
Write-Output "$(Get-Date -format s) :: Sorted VM start list"
$AllVMListSorted

##Start VMs block
Write-Output "$(Get-Date -format s) :: Start VM now"

Foreach ($VM in $AllVMListSorted) {
	Write-Output "$(Get-Date -format s) :: Start VM: $($VM.VMName) :: $($VM.ResourceGroupName) :: $($VM.Subscriptionid)"
	Select-AzureRmSubscription -Subscriptionid $VM.Subscriptionid
	Start-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.VMName
	Start-Sleep -s 120
}


Write-Output "$(Get-Date -format s) :: Done VM start"