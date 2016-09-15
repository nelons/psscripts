param([String] $VIServer,
	  [String] $VIContainer,
	  [System.Management.Automation.PSCredential] $cred
	  )

## VMWare PowerCLI must be installed. Add the modules.
Add-PSSnapin VMware.VimAutomation.Core -erroraction silentlycontinue

## Connect to the server.
Connect-VIServer $VIServer -Credential $cred | out-null

## Create a new VIProperty for the VLAN (to make things easier to get)
New-VIProperty -name VlanId -ObjectType DistributedPortGroup -Value { $Args[0].ExtensionData.Config.DefaultPortConfig.Vlan.VlanId } -Force | out-null

## Get the VM's in the Container.
$vms = Get-VM -Location $VIContainer
if ($vms -eq $null) {
	Write-Host "No VMs to rollup.";
	Exit;
	
} elseif ($vms -isnot [system.array]) {
	$my_vm = $vms;
	$vms = @($my_vm);

}

foreach ($vm in $vms) {
	#if (-Not $vm.Name.StartsWith("lo-vpc-nlon")) {
	#	continue;
	#}

	$note = "*Auto-Gen*`n";
	
	# Get Annotations
	$anno = get-annotation $vm | where { $_.Value.Length -ne 0 }
	foreach ($a in $anno) {
		#if ($a.Name -eq "MO.Folder" -And $a.Value -ne $folder_path) {
		#	$note += "MO.Folder=$folder_path`n";
		#	Set-Annotation -Entity $vm -CustomAttribute "MO.Folder" -Value $folder_path;
		#	
		#} elseif ($($a.Value).Length -gt 0) {
		#	# Assemble string and add to the note.
		#	$note += "$($a.Name)=$($a.Value)`n";	
		#}
		
		# Assemble string and add to the note.
		$note += "$($a.Name)=$($a.Value)`n";		
	}
		
	# Get the Network Adapters (this sorts them by adapter number where 10 > 2)
	$nics = get-networkadapter $vm | sort-object { if ($_.Name -match '(\d+)') { [int] $matches[1] } }
	$vlans = ""
	
	# Look at each nic to get the VLAN
	foreach ($nic in $nics) {
		# See if we need to add a comma
		if ($vlans.Length -ne 0) {
			$vlans += ","
		}
		
		try {
			# Get the Portgroup.
			$distributed_portgroup = $true;
			$pg = Get-VirtualPortGroup -Name $($nic.NetworkName) -Distributed -ea SilentlyContinue			
			if ($pg -eq $Null) {
				$pg = Get-VirtualPortGroup -Name $($nic.NetworkName)
				if ($pg -ne $Null) {
					$distributed_portgroup = $false;
				
				}
			}
			
			if ($pg -ne $Null) {
				if ($distributed_portgroup -eq $False) {
					$vlans += "S";
					
				}
			
				if ($($pg.VlanId.GetType().Name) -eq "NumericRange") {
					# Add the range for the VLAN's
					$vlans += "$($pg.VlanId.Start)-$($pg.VlanId.End)";
				
				} else {
					# Single VLAN value. Add to the list.
					$vlans += $($pg.VlanId);
					
				}
				
			} else {
				$vlans += "x";
			
			}
			
		} catch {
			# Add an 'x' to symbolise that there is no VLAN on this portgroup.
			$vlans += "x";
		}
	}
	
	if ($vlans.Length -ne 0) {
		$note += "VLANS=$vlans`n"
	}
	
	# Assemble the Folder path.
	$current_folder = $vm.Folder;
	$folder_path = "";
	while ($current_folder.Parent -ne $null) {
		if ($current_folder.Parent.Name -eq "vm") {
			break;
		}

		if ($folder_path.Length -ne 0) {
			$folder_path = $folder_path.Insert(0, "\");
		
		}
		
		$folder_path = $folder_path.Insert(0, $current_folder.Name);
		$current_folder = $current_folder.Parent;		
	}

	if ($folder_path.Length -ne 0) {
		$note += "FolderPath=$folder_path";
	}
	
	## This sets the Notes field. Uncomment when necessary ;)
	##if ($vm.Name.StartsWith("lo-vpc-nlon")) {
		Set-VM -vm $vm -Description $note -Confirm:$False | out-null
	##}
}

## Disconnect
Disconnect-VIServer -Confirm:$False