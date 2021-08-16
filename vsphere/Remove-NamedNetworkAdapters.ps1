param([string] $VMName,
      [string] $VMLocation,
      [Parameter(Mandatory=$true)][string] $NetworkName,
      [switch] $WhatIf)

<#
    param: vm name. if blank, get them all.
    param: network name. to match the name of the network to remove.

    Uses code from LucD from the following location:
    https://communities.vmware.com/t5/VMware-PowerCLI-Discussions/Remove-network-adapter-from-running-vm/td-p/1269138
#>

# Ensure connected.
if ($global:DefaultVIServers.Count -eq 0) {
    Write-Output "There are no connected VI Servers. Connect to one using Connect-VIServer and then run this script again.";
    exit;
}

# Get the VMs
$vms = @();
if ($null -ne $VMName -And $VMName.Length -gt 0) {
    if ($null -ne $VMLocation -And $VMLocation.Length -gt 0) {
        # Get VMs by Name and Location
        $vms = Get-VM $VMName -Location $VMLocation | Sort-Object Name;
    } else {
        # Get VMs only by Name
        $vms = Get-VM $VMName | Sort-Object Name;
    }

} elseif ($null -ne $VMLocation -And $VMLocation.Length -gt 0) {
    # Gets VMs only by Location
    $vms = Get-VM -Location $VMLocation | Sort-Object Name;

} else {
    # Get all VMs.
    $vms = Get-VM | Sort-Object Name;

}

# Loop through the VMs and disconnect any found adapters.
$vms | ForEach-Object { 
    $vm = $_;
    $adapters = $vm | Get-NetworkAdapter | Where-Object { $_.NetworkName.StartsWith($NetworkName); }
    if ($null -ne $adapters) { 
        $adapters | ForEach-Object {
            $adapter_name = $_.Name;
            $network_name = $_.NetworkName;
            $nic = $vm.ExtensionData.Config.Hardware.Device | Where-Object {$_.DeviceInfo.Label -eq $adapter_name };
            if ($null -ne $nic) {
                if ($WhatIf -eq $False) {
                    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec;
                    $dev = New-Object VMware.Vim.VirtualDeviceConfigSpec;
                    $dev.operation = "remove";
                    $dev.Device = $nic;
                    $spec.DeviceChange += $dev;
                    $vm.ExtensionData.ReconfigVM($spec);
                    Write-Host "$($vm.Name) - disconnected $adapter_name" -Foreground Green;

                } else {
                    Write-Host "WHATIF - $($vm.Name) - want to disconnect $adapter_name on network $network_name";

                }
            }
        }
    }
}
