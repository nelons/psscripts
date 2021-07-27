# Configuration variables.
# The FQDN (or IP) of your vCenter Server.
$vCenterServer = "vcenter.dnsname";
$ClusterName = "cluster";

# An array of datastore names that you want to convert.
$datastores = @("Datastore Name");

# When should the path be switched ?
$iops_switch = 1;

Connect-VIServer $vCenterServer | out-null;
$hosts = Get-VMHost -Location $ClusterName | Where-object {($_.ConnectionState -like "Connected")} | Sort-Object Name

# This will get the datastores from the array at the top of the file. 
$ds_id = $datastores | ForEach-Object { Get-Datastore -Name $_ } | ForEach-Object { return $_.ExtensionData.Info.Vmfs.Extent.DiskName; }

# Uncomment this line if you want to ignore the datastore name array
# and instead filter on the start of the datastore name.
# Remember to update the part of the line that starts with "start of datastore name" !
# Remember to comment out the datastore array line above !
#$ds_id = $datastores | ForEach-Object { Get-Datastore | { $_.Name.StartsWith("Start of datastore name"); } } | ForEach-Object { return $_.ExtensionData.Info.Vmfs.Extent.DiskName; }

$hosts | ForEach-Object { 
    $esx = $_;
    Write-Output "$($esx.Name): Checking LUNs.";

    $ds_id | ForEach-Object {
        $lun = $esx | Get-SCSILun -LunType Disk -CanonicalName $_;
        if ($null -ne $lun) {
            # Make sure it is RoundRobin
            if ($($lun.MultipathPolicy) -notlike “RoundRobin”) {
                Write-Output "$($esx.Name), $($_): Setting multipath policy to RoundRobin.";
                $lun | Set-ScsiLun -MultipathPolicy RoundRobin | out-null;
            }

            if ($($lun.CommandsToSwitchPath) -ne $iops_switch) {
                # Set the IOPS switch.
                Write-Output "$($esx.Name), $($_): Settings commands to switch path parameter to 1.";
                $lun | Set-ScsiLun -CommandsToSwitchPath $iops_switch | out-null;
            }
        }
    }
}

Disconnect-VIServer -Force -Confirm:$False;
