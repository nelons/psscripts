param([string] $VMName,
      [Parameter(Mandatory=$true)][string] $NetworkName)

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
    $vms = Get-VM $VMName;
} else {
    $vms = Get-VM | Sort-Object Name;
}

# Loop through the VMs and disconnect any found adapters.
$vms | ForEach-Object { 
    $vm = $_;
    $adapters = $vm | Get-NetworkAdapter | Where-Object { $_.NetworkName.StartsWith($NetworkName); }
    if ($null -ne $adapters) { 
        $adapters | ForEach-Object {
            $adapter_name = $_.Name;
            $nic = $vm.ExtensionData.Config.Hardware.Device | Where-Object {$_.DeviceInfo.Label -eq $adapter_name };
            if ($null -ne $nic) {
                $spec = New-Object VMware.Vim.VirtualMachineConfigSpec;
                $dev = New-Object VMware.Vim.VirtualDeviceConfigSpec;
                $dev.operation = "remove";
                $dev.Device = $nic;
                $spec.DeviceChange += $dev;

                Write-Output "$($vm.Name) - disconnecting $adapter_name";
                $vm.ExtensionData.ReconfigVM($spec);
            }
        }
    }
}