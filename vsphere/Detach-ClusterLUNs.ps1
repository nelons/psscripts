param(
	[Parameter(Mandatory=$true,ValueFromPipeline)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl] $Cluster,
	[Parameter(Mandatory=$true)][String[]] $LUNIdentifiers,
	[switch]$CheckUsage = $false
)

$vms = $Cluster | Get-VM;
$cluster_host = $Cluster | Get-VMHost | sort Name | select -First 1

$LUNs_To_Detach = @();
$LUNIdentifiers | % {
	$lunid = $_;
	$lun = get-scsilun -VMHost $cluster_host | ? { $_.CanonicalName -eq $lunid }
	if ($lun -ne $null) {
		$attached = $false;

		Write-Host "Looking for Datastores on LUN $_";
		$cluster_host | Get-Datastore | ? {
			$ds = $_;
			if ($ds.ExtensionData.Info.vmfs) {
				# TODO: Fix this for extents.
				if ($ds.ExtensionData.Info.vmfs.Extent[0].DiskName -eq $lunid) {
					Write-Host "Datastore $($ds.Name) is on this LUN";
					$attached = $true;
				}			
			}			
		}		

		if ($attached -eq $false) {
			Write-Host "Looking for VMs attached to LUN $_";	
			$vms | % {
				$v = $_ | Get-View;		
				$rdms = $v.Config.Hardware.Device | ? { $_.Backing -ne $null -And $_.Backing.GetType().Name -eq "VirtualDiskRawDiskMappingVer1BackingInfo" }
				
				$exists = $rdms | ? { 
					$rdm = $_;
					return $lun.ExtensionData.Descriptor | ? { $_.Id -eq $rdm.Backing.DeviceName };
				}
				
				if ($exists.Count -gt 0) {
					Write-Host "LUN is connected to $($v.Name)";
					$attached = $true;
				}
			}
		}
		
		if ($attached -eq $false) {
			Write-Host "LUN is not attached to any VM in the cluster and does not have a Datastore on it.";
			$LUNs_To_Detach += $lunid;
		}
	} else {
		Write-Host "Could not find a LUN for the device name $lunid";
		
	}
}

if ($CheckUsage = $false -And $LUNs_To_Detach.Count -gt 0) {
	#Write-Host "Detaching $($LUNs_To_Detach.Count) LUNs";
	$Cluster | get-vmhost | sort Name | % {
		write-host "Detaching LUNs from $($_.Name)" -Foreground Yellow
		$esx = $_;
		
		$storSys = Get-View $_.Extensiondata.ConfigManager.StorageSystem
		
		foreach ($lunid in $LUNs_To_Detach){				
			$lun = Get-ScsiLun -VmHost $esx | ? { $_.CanonicalName -eq $lunid }
			if ($lun -ne $null) {
				# Ensure the LUN is attached 
				if ($lun.ExtensionData.OperationalState -eq "ok") {
					write-host "Detaching LUN $lun" # from $($esx.Name)"
					$storSys.DetachScsiLun($lun.ExtensionData.Uuid)
					write-host "Detach Complete" -Foreground Green
					
				} elseif ($lun.ExtensionData.OperationalState -eq "off") {
					Write-Host "LUN is already unmounted on this host." -Foreground Green;
					
				} else {
					Write-Host "OperationalState is $($lun.ExtensionData.OperationalState)";
					
				}
				
			} else {
				Write-Host "Could not find LUN $lun on host $esx.Name";
			}
		}
	}
}
