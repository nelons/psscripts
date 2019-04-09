Import-Module Cisco.UCSCentral;

Get-UCSCentralOrgDomainGroup -Filter { Level -ceq 1 } | % {
	$group = $_;
	Get-UCSCentralComputeSystem | ? { $_.OperGroupDn.StartsWith($group.Dn); } | % {
		$compute = $_;
		Get-UCSCentralChassis -ComputeSystem $_ | sort Id | select @{L='Group';E={$group.name}}, @{L='Domain';E={$compute.Name}}, @{L='Chassis';E={ $_.Id}}, @{L='Blade Count';E={(Get-UCSCentralBlade -Chassis $_).Count}}
	}
}