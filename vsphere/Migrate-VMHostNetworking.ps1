param([string] $vCenterServer,
      [string] $ClusterName,
      [string[]] $IncludedHosts,
      [string] $vDSName,
      [string] $SourceStandardSwitch,
      [switch] $IgnoreISCSIWarnings,
      [switch] $WhatIf)

Import-Module VMware.VimAutomation.Core;
Import-Module VMware.VimAutomation.Vds;

$vc = $null;
$using_existing = $false;

if ($vCenterServer -ne $null -And $vCenterServer.Length -gt 0) {
    #Write-Host "Attempting to connect to $vCenterServer";
    $exists = $global:DefaultVIServers.Name | ? { $_ -eq $vCenterServer };
    if ($exists -eq $null) {
        Write-Host "There is no existing connection to $vCenterServer. Creating a new one.";
        $vc = Connect-VIServer -Server $vCenterServer;

    } else {
        #Write-Host "Already connected to $vCenterServer. Using the connection :)" -ForegroundColor Green;
        $using_existing = $true;
        $vc = $global:DefaultVIServer | ? { $_.ServiceUri.Host -eq $vCenterServer };

    }

} else {
    $connected_count = $global:DefaultVIServers.Count;
    if ($connected_count -eq 1) {
        # TODO: Ask if we want to use the current connection.
        $using_existing = $true;
        $vc = $global:DefaultVIServers[0];

    } elseif ($connected_count -eq 0) {
        # TODO: Prompt for vCenter Name

    } else {
        # TODO: Show a list of available vCenter Servers and ask which one.

    }
}

if ($vc -ne $null) {
    if ($using_existing -eq $true) {
        Write-Host "Using existing connection to vCenter Server $($vc.Name)." -ForegroundColor Green;

    } else {
        Write-Host "Connected to vCenter Server $($vc.Name)."  -ForegroundColor Green;

    }

} else {
    Write-Host "Could not connect to a vCenter Server." -ForegroundColor Red;
    exit;
}

$cluster_count = $(Get-Cluster -Server $vc).Count;
if ($cluster_count -eq 0) {
    Write-Host "There are no clusters in the vCenter Server." -ForegroundColor Red;
    exit;

} elseif ($cluster_count -gt 1) {
    if ($ClusterName -eq $null -Or $ClusterName.Length -eq 0) {
        Write-Host "`nClusters on this vCenter Server:" -ForegroundColor Yellow;
        $cl = Get-Cluster -Server $vc | Select -ExpandProperty Name;
        $k = 0;

        $cl | % {
            Write-Host "$k`: $_";
            $k++;
        }

        $chosenk = Read-Host "Please enter the number for the cluster you wish to work on";
        if ($chosenk -ge 0 -And $chosenk -lt $cl.Count) {
            $ClusterName = $cl[$chosenk];
            Write-Host "You chose cluster $ClusterName.`n" -ForegroundColor Green;
        }
    }

} else {
    $ClusterName = $(Get-Cluster -Server $vc).Name;
    Write-Host "There is only one cluster - using $ClusterName.";

}

# ESXi hosts to migrate from VSS to VDS
if ((Get-Cluster $ClusterName -Server $vc -ErrorAction SilentlyContinue) -eq $null) {
    Write-Host "The Cluster name '$ClusterName' does not match a cluster on the vCenter Server." -ForegroundColor Red;
    exit;
}

$vmhost_array = Get-VMHost -Location $ClusterName -Server $vc | Sort Name;
if ($vmhost_array -eq $null -Or $vmhost_array.Count -eq 0) {
    Write-Host "There was a problem getting the list of hosts in the cluster $ClusterName." -ForegroundColor Red;
    exit;
}

$vds = $null;
$vds_count = $(Get-VDSwitch -Server $vc).Count;
if ($vds_count -eq 0) {
    Write-Host "No Virtual Distributed Switches exist." -ForegroundColor Red;
    exit;

}
elseif ($vds_count -gt 1) {
    if ($vDSName -eq $null -Or $vDSName.Length -eq 0) {
        Write-Host "Virtual Distributed Switches in this vCenter Server`:" -ForegroundColor Yellow;
        Get-VDSwitch -Server $vc | Select -ExpandProperty Name;
        $vDSName = Read-Host "Please enter the name of the Virtual Distributed Switch";
    }

    $vds = Get-VDSwitch $vDSName -Server $vc -ErrorAction SilentlyContinue;
    # Get the VDS
    if ($vds -eq $null) {
        Write-Host "A virtual distributed switch with the name $vdsName could not be found..";
        exit;
    }
}
else {
    $vds = $(Get-VDSwitch -Server $vc)
    $vDSName = $vds.Name;
    Write-Host "There is only one vDS on this vCenter. Using $vDSName." -ForegroundColor Green;

}

<#
    This assigns a physical NIC to an uplink port on a VDS.
    The physical NIC is disconnected if used elsewhere

    $VMHost - ESXi Host
    $PhysicalNIC - The physical NIC to move.
    $VDSwitch - The distributed switch.
    $UplinkName - The name of the uplink to assign.
#>
Function AssignPhysicalNICToUplink {
    Param($VIServer, $VMHost, $PhysicalNIC, $VDSwitch, $UplinkName)
    Process {
        $uplinks = Get-VDPort -VDSwitch $VDSwitch -Uplink -Server $VIServer | where {$_.ProxyHost -eq $VMHost}

        $uplink = $uplinks | ? { $_.Name -eq $UplinkName };
        if ($uplink -ne $null) {
            if ($uplink.ConnectedEntity -ne $null) {
                Write-Host "This uplink is already assigned to a physical NIC." -ForegroundColor Red;

            } else {
                $PhysicalNIC | Remove-VirtualSwitchPhysicalNetworkAdapter -Confirm:$False -ErrorAction SilentlyContinue | out-null;

                $config = New-Object VMware.Vim.HostNetworkConfig

                $proxy = New-Object VMware.Vim.HostProxySwitchConfig
                $proxy.Uuid = $vds.ExtensionData.Uuid
                $proxy.ChangeOperation = [VMware.Vim.HostConfigChangeOperation]::edit
                $proxy.Spec = New-Object VMware.Vim.HostProxySwitchSpec
                $proxy.Spec.Backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking

                # Add Existing Connected nics.
                $uplinks | ? { $_.ConnectedEntity -ne $null } | % {
                    $pnic = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
                    $pnic.PnicDevice = $_.ConnectedEntity;
                    $pnic.UplinkPortKey = $_.Key;
                    $proxy.Spec.Backing.PnicSpec += $pnic
                }
                
                # Add the new nic.
                $pnic = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
                $pnic.PnicDevice = $PhysicalNIC.Name;
                $pnic.UplinkPortKey = $uplink.Key
                
                $proxy.Spec.Backing.PnicSpec += $pnic
                $config.ProxySwitch += $proxy
                
                $x = $netSys.UpdateNetworkConfig($config, [VMware.Vim.HostConfigChangeMode]::modify);
            }
        } else {
            Write-Host "Could not find an uplink with the name '$UplinkName'" -ForegroundColor Red;

        }
    }
}

$DestinationPortgroups = @();
$StandardSwitchNames = @();

$vmhost_array | % {
    $vmhost = $_;
    $find_vswitches = $false;

    # TODO: Test if the host is included
    if ($IncludedHosts.Count -gt 0) {
        $found = $IncludedHosts | ? { $_ -eq $vmhost.Name };
        if ($found -ne $null) {
            $find_vswitches = $true;
        }
    } else {
        $find_vswitches = $true;
    }

    if ($find_vswitches -eq $true) {
        $vss_array = $_ | Get-VirtualSwitch -Standard -Server $vc;
        if ($vss_array -ne $null -And $vss_array.Count -gt 0) {
            $vss_array | % {
                $StandardSwitchNames += $_.Name;
            }
        }
    }
}

$StandardSwitchNames = $StandardSwitchNames | Select -Unique;

$vss_prompt = $false;
if ($SourceStandardSwitch -ne $null -And $SourceStandardSwitch.Length -gt 0) {
    $vss_found = $StandardSwitchNames | ? { $_ -eq $SourceStandardSwitch };
    if ($vss_found -eq $null) {
        Write-Host "Cannot find the standard switch $SourceStandardSwitch in the cluster." -ForegroundColor Red;
        $vss_prompt = $true;
    }
}

if ($vss_prompt -eq $true -Or ($SourceStandardSwitch -eq $null -Or $SourceStandardSwitch.Length -eq 0)) {
    if ($StandardSwitchNames.Count -eq 1) {
        $SourceStandardSwitch = $StandardSwitchNames;
        Write-Host "There is only one Virtual Standard Switch on the host - Using $SourceStandardSwitch." -ForegroundColor Green;       

    } else {
        # TODO: Select a Name for the standard switch.
        Write-Host;
        Write-Host "The standard switches on the hosts in cluster $ClusterName`:" -ForegroundColor Yellow;

        $x = 0;
        $StandardSwitchNames | % {
            Write-Host "$x`: $_";
            $x++;
        }

        while ($true) {           
            $vss_choice = $(Read-Host "Please select a standard switch to migrate");
            if ($vss_choice.Length -gt 0) {
                try {
                    $vss_choice = [int]$vss_choice;

                    if ($vss_choice -ge 0 -And $vss_choice -lt $StandardSwitchNames.Count) {
                        $SourceStandardSwitch = $StandardSwitchNames[$vss_choice];
                        Write-Host "The Virtual Standard Switch $SourceStandardSwitch was chosen." -ForegroundColor Green;
                        break;

                    } else {
                        Write-Host "Please enter a number between 0 and $($StandardSwitchNames.Count)" -ForegroundColor Red;
                    }
                } catch {
                    Write-Host "The choice '$vss_choice' is not a valid number." -ForegroundColor Red;
                }
            }
        }    
    }
}

if ($SourceStandardSwitch.Length -gt 0) {
    # Get the portgroups/etc from each host with the switch and report.
    Write-Host "`nThe vSwitch '$SourceStandardSwitch' has the following portgroups:"

    $host_pgs = $null;
    if ($IncludedHosts -ne $null -And $IncludedHosts.Count -gt 0) {
        $host_pgs = $IncludedHosts;

    } else {
        $host_pgs = $vmhost_array | select -expandproperty Name;

    }

    # Reduce this to select hosts/clusters.
    $pgs = @();
    Get-VirtualPortGroup -Standard -VirtualSwitch $SourceStandardSwitch | ? {
        $h = Get-VMHost -Id $_.VirtualSwitch.VMHostId;
        if ($host_pgs -contains $h.Name) {
            $pgs += $_ | select Name, VLanId;
        }
    }

    $pgs = $pgs | sort -property Name | select Name, VLanId -Unique

    $pgs | % {
        Write-Host "$($_.Name) (VLAN $($_.VLanId))";
    }
    Write-Host;
}

$vmnic_mapping = @();
$vmk_mapping = @();

# For each Host, see what we can do.
$vmhost_array | % {
    $vmhost = $_;

    # See if this host is one we want to examine.
    if ($IncludedHosts.Count -gt 0) {
        $found = $IncludedHosts | ? { $_ -eq $vmhost };
        if ($found -eq $null) {
            # No.
            #Write-Host "$vmhost is not specified for changes to made. Skipping.";
            return;

        }
    }

    Write-Host "Evaluating changes for host $($vmhost.Name)";

    # Is this host connected to the VD switch ?
    $attached = $vds.ExtensionData.Summary.HostMember | ? { $(Get-VMHost -Id $_) -eq $vmhost };
    if ($attached -eq $null) {
        Write-Host "Attaching $($vmhost).Name to VD Switch" -ForegroundColor Yellow;
        Add-VDSwitchVMHost -VDSwitch $vds -VMHost $vmhost -Confirm:$False | out-null;
    }

    # Get the uplink count.
    $uplinks = $vds | get-vdport -uplink -Server $vc | ? { $_.ProxyHost -eq $vmhost }
    $vds_uplink_count = $uplinks.count;
    #Write-Host "There are $vds_uplink_count uplinks on the Distributed Switch.";

    # Get the Source Standard Switch.
    $vss = $vmhost | Get-VirtualSwitch -Name $SourceStandardSwitch -Server $vc -ErrorAction SilentlyContinue;
    if ($vss -ne $null) {
        #Write-Host "Found standard switch $SourceStandardSwitch on host $($vmhost.Name)";

        # Get the number of NICs allocated to the switch.
        $vss_uplinks = $vmhost | Get-VMHostNetworkAdapter -Server $vc -Physical -VirtualSwitch $vss;
        $vss_uplink_count = $vss_uplinks.Count;
        Write-Host "There are $vss_uplink_count uplinks on the Standard Switch $SourceStandardSwitch on host $($vmhost.Name).";

        # Only continue if we have more than 0 uplinks
        if ($vss_uplink_count -eq 0) {
            continue;
        }

        # Check if we need to map uplinks.
        $do_mapping = $false;
        if ($vmnic_mapping.Count -eq 0) {
            $do_mapping = $true;

        } else {
            # Ensure that these are the NICs attached to the vSwitch and we have a mapping.
            $vss_uplinks | % {
                $vmnic = $_;
                $uplink_mapped = $vmnic_mapping | ? { $_.vmnic -eq $vmnic.Name }
                if ($uplink_mapped -eq $null) {
                    Write-Host "The host $($vmhost.Name) has a different uplink setting for standard switch $SourceStandardSwitch";
                    exit;
                }
            }
        }

        if ($do_mapping -eq $true) {        
            Write-Host "Host '$($vmhost.Name)' is using the following Uplinks on $vdsName";    
            $vdports = Get-VDPort -Server $vc -VDSwitch $vds -Uplink | where {$_.ProxyHost -eq $vmhost } | Sort Name | Select Name, ConnectedEntity;

            $j = 0;
            $vdports | % {
                Write-Host "$j`: $($_.Name) `($($_.ConnectedEntity)`)";
                $j++;
            }
            Write-Host;

            $vss_uplinks | % {
                while ($true) {
                    $pnicName = $_.Name;        
                    $choice = Read-Host -Prompt "Type the number for the unused portgroup that $pnicName should be mapped to ?"
                    if ($choice -ge 0 -And $choice -lt $($vdports.Count)) {
                        # Ensure there isn't already a mapping for it.
                        $uplinkName = $($vdports[$choice]).Name;
                        Write-Host "Uplink $uplinkName has been selected for $pnicName." -ForegroundColor Green;

                        ## TODO: validate this isn't used across other hosts.
                        
                        if ($uplinkName.Length -gt 0) {
                            # Should also check the uplinks are unused.
                            if ($(Get-VDPort -VDSwitch $vds -Server $vc -Uplink | ? { $_.ProxyHost -eq $vmhost -And $_.ConnectedEntity -eq $null -And $_.Name -eq $uplinkName }) -ne $null) {                                    
                                if ($uplinkName -ne $null) {
                                    $map = "" | Select vmnic, uplinkName, vmhost;
                                    $map.vmnic = $_.Name;
                                    $map.uplinkName = $uplinkName;
                                    $vmnic_mapping += $map;
                                    break;

                                }
                            } else {
                                Write-Host "Invalid Uplink name." -ForegroundColor Red;

                            }
                        }
                    }  
                }
            }
        }



        # Get the Portgroups on the switches.
        $pgs = $vss | Get-VirtualPortGroup -Server $vc;
        if ($pgs.Count -gt 0) {
            Write-Host "`nThe Distributed PortGroups are" -ForegroundColor Yellow;                    
            $choices = $vds | Get-VDPortgroup -Server $vc | sort Name | Select -ExpandProperty Name;
            $i = 0;
            $choices | % {
                Write-Host "$i`: $_";
                $i++;
            }            
        }

        $pgs | % {
            $vpg = $_;
            $dest = $null;
            if ($DestinationPortgroups.Count -gt 0) { 
                $dest = $DestinationPortgroups | ? { $_[0] -eq $vpg.Name } 
            }

            if ($dest -eq $null) {
                $pg_added = $false;
                while ($pg_added -eq $false) {                    
                    # Prompt for the name of a distributed port group to map this standard port group to.
                    $pg_choice = [int]$(Read-Host -Prompt "Enter the number for the destination port group for $($vpg.Name)");
                    #Write-Host "The choice was $pg_choice and should be between 0 and $($choices.Count)";
                    if ($pg_choice -ge 0 -And $pg_choice -lt $choices.Count) {
                        $dest_pg = $choices[$pg_choice];

                        # Ensure the $dest_pg exists on the vDS.
                        #$checked_pg = $vds | Get-VDPortgroup | ? { $_.Name -eq $dest_pg };
                        #if ($checked_pg -ne $null) {
                            Write-Host "Portgroup $dest_pg has been selected for $($vpg.Name)" -ForegroundColor Green;
                            $entry = @($($vpg.Name), $dest_pg);
                            $DestinationPortgroups += ,$entry;
                            $pg_added = $true;
                        #}
                    }
                }
            }
        }
    }
}

# TODO: ask/work out which vmnic to migrate first.
# Ideally check all portgroups and ensure there is redundancy.
# If there isn't, there will be an outage.



if ($WhatIf -ne $true) {
    $title = "Analysis is complete. Ready to migrate the standard switch networking to the VDS."
    $message = "Would you like to migrate networking ?"

    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "This means Yes"
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "This means No"
    $ro = New-Object System.Management.Automation.Host.ChoiceDescription "&ReadOnly", "Report on what changes will be made"

    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no, $ro)

    $result = $host.ui.PromptForChoice($title, $message, $Options, 0)

    Switch ($result)
    {
        #0 { "You just said Yes" }
        1 { exit; }
        2 { $WhatIf = $true; }
    }
}

Write-Host "`nStarting to make changes." -ForegroundColor Green;

# Ensure DRS is disabled.
$drs_enabled = get-cluster $ClusterName -Server $vc | select -ExpandProperty DrsEnabled
$previous_drs = get-cluster $ClusterName | select -ExpandProperty DrsAutomationLevel;
if ($drs_enabled -eq $true -And $previous_drs -ne "Manual" -And $WhatIf -eq $false) {
    Write-Host "DRS has been disabled for the Cluster $ClusterName" -ForegroundColor Yellow;
    Set-Cluster $ClusterName -DrsAutomationLevel Manual -Confirm:$False | Out-Null;
}

# Now we have all the mappings, it's time to do something about it.
# For each Host, see what we can do.
$vmhost_array | % {
    $vmhost = $_;

    # See if this host is one we want to examine.
    if ($IncludedHosts.Count -gt 0) {
        $found = $IncludedHosts | ? { $_ -eq $vmhost };
        if ($found -eq $null) {
            return;
        }
    }

    $netSys = Get-View -Id $vmhost.ExtensionData.ConfigManager.NetworkSystem
    Write-Host "`nStarting to migrate networking on host $($vmhost.Name)";

    # Get the Source Standard Switch.
    $vss = $vmhost | Get-VirtualSwitch -Name $SourceStandardSwitch -Server $vc -ErrorAction SilentlyContinue;
    if ($vss -ne $null) {
        # Move the first NIC to the vDS ?
        $vss_uplinks = $vmhost | Get-VMHostNetworkAdapter -Server $vc -Physical -VirtualSwitch $vss;

        # Is there any ISCSI on this vSwitch ?
        $iscsi_hba = $vmhost | Get-VMHostHBA -Type iSCSI;
        Write-Host "Total number of iSCSI adapters on the host: $($iscsi_hba.Count)" -ForegroundColor Red;

        $cli = Get-ESXCli -VMHost $vmhost -V2;
        $iscsi_bindings = @();
        if ($iscsi_hba.Count -gt 0) {
            # Yes.
            $iscsi_hba | % {
                # Remove the binding ?
                $hba = $_;

                # Not sure - might need @{"adapter" = $hba} as the parameter.
                $bindings = $cli.iscsi.networkportal.list.invoke();
                $bindings | ? { $_.Vswitch -eq $vss.Name} | % {
                    Write-Host "Found an iSCSI binding on the virtual switch." -ForegroundColor Red;
                    $binding = $_;                    
                    # There is a iSCSI 
                    $entry = "" | select Adapter, vmk, Status;
                    $entry.Adapter = $binding.Adapter;
                    $entry.vmk = $binding.vmknic;
                    $entry.Status = "bound";
                    $iscsi_bindings += $entry;
                }
            }

            $migrate_binding = $false;
            if ($iscsi_bindings.Count -ge 2) {
                # Disconnect one of them.
                Write-Host "Disconnecting binding for vmknic $($iscsi_bindings[0].vmk)" -ForegroundColor Red;
                $migrate_binding = $true;

            } elseif ($iscsi_bindings.Count -eq 1) {
                Write-Host "There is only one iSCSI binding. Moving the adapter will cause an outage for any VMs using attached storage." -ForegroundColor Red;

                if ($IgnoreISCSIWarnings -eq $false) { 
                    Write-Host "Set `$IgnoreISCSIWarnings to true to ignore this warning and migrate anyway." -ForegroundColor Red;
                    Write-Host "Aborting migration on this host.";
                    return;
                } else {
                    $migrate_binding = $true;
                }
            }

            if ($WhatIf -eq $false -And $migrate_binding -eq $true) {
                $binding = $iscsi_bindings[0];                
                $unbind_result = $cli.iscsi.networkportal.remove.invoke(@{"adapter"="$($binding.Adapter)";"force"="true";"nic"="$($binding.vmk)"});
                if ($unbind_result -eq $false) {
                    Write-Host "Failed to unbind the iSCSI vmk from the adapter." -ForegroundColor Red;

                    if ($IgnoreISCSIWarnings -eq $false) {
                        Write-Host "Aborting migration on this host.";
                        return;
                    }
                } else {
                    Write-Host "Unbound $($binding.vmk) from iSCSI adapter '$($binding.Adapter)'";
                    $iscsi_bindings[0].Status = "unbound";                    

                }                
            }
        }

        # TODO: Should we only move a NIC if there is no current portgroup connectivity ?

        # This is the NIC we will migrate.
        $migrate_nic = 0;

        # Do we have any standby NICs ?    
        $standby = Get-NICTeamingPolicy -VirtualSwitch $vss -Server $vc | Select -ExpandProperty StandbyNIC;
        if ($standby -ne $null -And $standby.Count -gt 0) {
            $migrate_nic = $vss_uplinks | ? { $_.Name -eq $($standby | select -first 1) };        

        } else {
            # There are only active links
            # Because we are ignoring the unused.
            if ($vss_uplinks.Count -gt 0) {
                # If there is a management interface here but nowhere else then we might have a problem.
                $migrate_nic = $vss_uplinks[0];

            }
        }

        # Use the global map.
        $vmnic_map = $vmnic_mapping | ? {
            $migrate_nic.Name -eq $_.vmnic
        }

        if ($vmnic_map -ne $null) {
            # TODO: don't do this if only one uplink ?

            $not_complete = $false;
            Write-Host "Migrating NIC $migrate_nic...";
            if ($WhatIf -eq $false) {
                AssignPhysicalNICToUplink -VIServer $vc -VMHost $vmhost -PhysicalNIC $migrate_nic -VDSwitch $vds -UplinkName $vmnic_map.uplinkName;

            }

            if ($WhatIf -eq $false) {
                Sleep(5);
            }

            # Move VMs
            Write-Host "Moving VMs.";
            $vss | Get-VirtualPortGroup -Server $vc | % {
                $vpg = $_;

                # Get the Mapping
                $vm_map = $DestinationPortgroups | ? { $_[0] -eq $vpg.Name };
                if ($vm_map -ne $null) {
                    $vdspg = Get-VDPortgroup -Server $vc -Name $vm_map[1];                    

                    $vms = $vmhost | Get-VM | ? { $_ | Get-NetworkAdapter | ? { $_.NetworkName -eq $vpg.Name } };
                    $vms | % {
                        Write-Host "Migrating '$($_.Name)' from $($vpg.Name) to $($vdspg.Name)";

                        ## Change
                        if ($WhatIf -eq $False) {
                            $_ | Get-NetworkAdapter | ? { $_.NetworkName -eq $vpg.Name } | Set-NetworkAdapter -Portgroup $vdspg -Confirm:$False | Out-Null; 

                        }
                    }
                }
            
                if ($WhatIf -eq $false) {
                    Start-Sleep -Seconds 5
                }

                if ($WhatIf -eq $False) {
                    $vm_count = $vmhost | Get-VM | ? { $_ | Get-NetworkAdapter | ? { $_.NetworkName -eq $vpg.Name }};
                    if ($vm_count -eq $null -Or $vm_count -eq 0) {
                        # TODO: ensure there are no VMKs on this portgroup
                        $vmks_on_vpg = $vmhost | Get-VMHostNetwork | Select-Object Hostname, VMkernelGateway -ExpandProperty VirtualNic | where {$_.PortGroupName -match $vpg.Name };

                        if ($null -eq $vmks_on_vpg -Or $vmks_on_vpg.Count -eq 0) {
                            # Remove the Portgroup.
                            $vpg | Remove-VirtualPortgroup -Confirm:$False;
                        }

                    } else {
                        Write-Host "There are still VMs left on $($vpg.Name)" -ForegroundColor Red;
                        $not_complete = $true;

                    }
                }
            }  

            # Move VMKernel Interface.
            $vmks = $vmhost | get-vmhostnetworkadapter -VMKernel -Server $vc | ? { $($vss | Get-VirtualPortGroup -Server $vc | select -expandproperty Name) -contains $_.PortGroupName }
            if ($vmks.Count -gt 0) {
                Write-Host "Migrating VMKernel Interfaces:";

            } else {
                Write-Host "There are no VMKernel interfaces to migrate.";

            }           

            $vmks | % {
                $vmk_name = $_.PortGroupName;

                # TODO: ignore if this is an ISCSI vmk.
                $vmk_iscsi = $iscsi_bindings | ? { $_.vmk -eq $vmk_name -And $_.Status -eq "bound" };
                if ($vmk_iscsi -ne $null) {
                    Write-Host "$vmk_name is used for iSCSI bindings and is still bound." -ForegroundColor Red;

                } else {                
                    # Find the mapping.
                    $vmk_map = $DestinationPortgroups | ? { $_[0] -eq $vmk_name }; #$vmk_mapping | ? { $_.VMKName -eq $vmk_name };
                    if ($vmk_map -ne $null) {                        
                        # Move the Adapter
                        Write-Host "Migrating VMK $($_.Name) ... to portgroup $($vmk_map[1])"
                        if ($WhatIf -eq $False) {
                            Set-VMHostNetworkAdapter -PortGroup $($vmk_map[1]) -VirtualNic $_ -Confirm:$False -ErrorAction SilentlyContinue -ErrorVariable a | out-null;
                        
                            if ($a -ne $null) {
                                Write-Host "There was an error moving the vmk adapter." -ForegroundColor Red;
                                Write-Host $a;
                                $not_complete = $true;

                            } else {
                                # TODO: check if the port group is still in use


                                # Remove the Portgroup.
                                $vpg = $vmhost | Get-VirtualPortGroup -Name $vmk_name -VirtualSwitch $vss;
                                Remove-VirtualPortGroup $vpg -Confirm:$False;

                            }
                        }
                    }
                }
            }

            # TODO: rebind the iSCSI vmk
            $unbound_iscsi = $iscsi_bindings | ? { $_.Status -eq "unbound" };
            $unbound_iscsi | % {
                # Bind it.
                $binding = $_;
                Write-Host "Rebinding vmk $($binding.vmk) to iSCSI adapter '$($binding.Adapter)'";

                $bind_result = $cli.iscsi.networkportal.add.invoke(@{"adapter"="$($binding.Adapter)";"force"="false";"nic"="$($binding.vmk)"});
                if ($bind_result -eq $true) {
                    $_.Status = "migrated";

                } else {
                    Write-Host "There was a proble rebinding the iSCSI adapter.";

                }

                # TODO: mark this as only being able to use one adapter ?
            }      

            if ($not_complete -eq $false) {
                # Move other VMNICS
                $vss_uplinks | % {
                    $vmnic = $_;
                    if ($vmnic -ne $migrate_nic) {
                        # Find the map for the vmnic
                        $map = $vmnic_mapping | ? { $_.vmnic -eq $vmnic.Name };
                        if ($map -ne $null) {
                            Write-Host "Migrating $vmnic to uplink $($map.uplinkName) ...";

                            if ($WhatIf -eq $False) {
                                AssignPhysicalNICToUplink -VIServer $vc -VMHost $vmhost -PhysicalNIC $vmnic -VDSwitch $vds -UplinkName $map.uplinkName;
                            }

                        } else {
                            Write-Host "Could not find a vmnic uplink map for vmnic $($vmnic.Name)" -Foreground Red;

                        }
                    }
                }

                # TODO: Move the other iSCSI VMKs

            
                # Delete the vSwitch
                if ($WhatIf -eq $False) {
                    $vss | Remove-VirtualSwitch -Confirm:$False;
                    Write-Host "The Standard Switch $SourceStandardSwitch has been deleted on host $($vmhost.Name)." -ForegroundColor Green;
                }
            }
            
            if ($iscsi_bindings.Count -gt 0 -And $WhatIf -eq $false) {
                # Rescan the adapter.
                Write-Host "Rescanning the Software iSCSI adapter.";
                $rescan_result = $cli.storage.core.adapter.rescan.invoke(@{"adapter"="$($iscsi_bindings[0].Adapter)"});
            }
        }
    }
}

# Re-enable DRS (if it was enabled before)
if ($drs_enabled -eq $true -And $previous_drs -ne "Manual" -And $WhatIf -eq $false) {
    Set-Cluster $ClusterName -DrsAutomationLevel $previous_drs -Confirm:$False;
    Write-Host "DRS has been re-enabled for the cluster $ClusterName" -ForegroundColor Green;
}

if ($exists -eq $False) {
    $vc | Disconnect-VIServer -Confirm:$False;
}

Write-Host "The script has completed." -ForegroundColor Green;