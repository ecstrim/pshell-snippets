# Define the name of the existing VM
$VMName = "SRV-DC05"

# Get the existing VM details
$VM = Get-VM -Name $VMName

# Create a custom object to store VM details
$NVM = [PSCustomObject]@{
    Name               = $VM.Name
    Path               = $VM.Path
    MemoryStartupBytes = $VM.MemoryStartupBytes
    ProcessorCount     = $VM.ProcessorCount
    VHDPaths           = (Get-VMHardDiskDrive -VMName $VMName | Select-Object -ExpandProperty Path)
    NetworkAdapters    = @()
}

# Get network adapter details
$VMNetworkAdapters = Get-VMNetworkAdapter -VMName $VMName

foreach ($Adapter in $VMNetworkAdapters) {
    $NetworkAdapterDetails = [PSCustomObject]@{
        SwitchName  = $Adapter.SwitchName
        VLANEnabled = $Adapter.EnableVlan
        VLANID      = $Adapter.VlanID
    }
    $NVM.NetworkAdapters += $NetworkAdapterDetails
}

Write-Output $NVM 

# Remove the VM but keep the VHD files
Remove-VM -Name $VMName -Force

# Recreate the VM with the same configuration
New-VM -Name $NVM.Name -MemoryStartupBytes $NVM.MemoryStartupBytes -Path $NVM.Path -Generation 2

# Set the processor count
Set-VMProcessor -VMName $NVM.Name -Count $NVM.ProcessorCount

# Attach the VHDs
foreach ($VHDPath in $NVM.VHDPaths) {
    Add-VMHardDiskDrive -VMName $NVM.Name -Path $VHDPath
}

# Add Network Adapters and configure VLAN settings
foreach ($Adapter in $NVM.NetworkAdapters) {
    Add-VMNetworkAdapter -VMName $NVM.Name -SwitchName $Adapter.SwitchName

    if ($Adapter.VLANEnabled) {
        Set-VMNetworkAdapterVlan -VMName $NVM.Name -Access -VlanId $Adapter.VLANID
    }
}

# Start the VM
Start-VM -Name $NVM.Name

# Optional: Display the VM information
Get-VM -Name $NVM.Name
