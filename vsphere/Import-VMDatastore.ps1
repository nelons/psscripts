<#
The aim of the script is to scan 1/more datastores and add all the VMs found to the inventory of a vCenter Server.
This can be useful as part of a DR process when failing mirrored LUNs over to another site,

Written By: Neale Lonslow
Date: 22nd October 2012
#>

param([Parameter(Mandatory=$true)][string] $vCenterServer,
	  [Parameter(Mandatory=$true)][string[]] $Datastores,
	  [Parameter(Mandatory=$true)][string] $TargetCluster,
	  [Parameter(Mandatory=$true)][string] $TargetResourcePool,
	  [Parameter(Mandatory=$true)][string] $TargetVMFolder)

# TODO: Check if module is imported.
$m = Get-Module "VMware.VIMAutomation.Core";

# TODO: Check if there is already a connection to a vCenterServer
$vctr = connect-viserver -server $vCenterServer | out-null


# Set the Host to the first Host in the Cluster.
$ESXHost = Get-Cluster $TargetCluster -Server $vctr | Get-VMHost | sort Name;
 
foreach($Datastore in $Datastores) {
   # Set up Search for .VMX Files in Datastore
   $ds = Get-Datastore -Name $Datastore -Server $vctr | %{Get-View $_.Id}
   $SearchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
   $SearchSpec.matchpattern = "*.vmx"
   $dsBrowser = Get-View $ds.browser
   $DatastorePath = "[" + $ds.Summary.Name + "]"
 
   # Find all .VMX file paths in Datastore, filtering out ones with .snapshot (Useful for NetApp NFS)
   $SearchResult = $dsBrowser.SearchDatastoreSubFolders($DatastorePath, $SearchSpec) | where {$_.FolderPath -notmatch ".snapshot"} | %{$_.FolderPath + ($_.File | select Path).Path}
 
   #Register all .vmx Files as VMs on the datastore
   $k = 0;
   foreach($VMXFile in $SearchResult) {
     Write-Host $VMXFile
     
     # Create the VM on a host (incrementing through hosts)
     New-VM -Server $vctr -VMFilePath $VMXFile -VMHost $ESXHost[$k % $ESXHost.Count] -Location $TargetVMFolder -ResourcePool $TargetResourcePool -RunAsync | Out-Null
     
	 # Required so that we create VMs on the next host. Prevents VMs all being registered to one host.
	 $k = $k + 1;
   }
}

disconnect-viserver $vctr -confirm:$false