param([Parameter(Mandatory=$true)][string] $vCenter,
      [System.Management.Automation.PSCredential] $Credential,
	  [string[]] $IncludeAddresses)
	 	  
if (!(Get-Module "VMware.vimautomation.core")) {
	if (Get-Module -ListAvailable -Name VMware.VIMAutomation.Core) {
		Import-Module VMware.VIMAutomation.Core;
	} else {
		Write-Error "VMware Automation Module not found.";
	}
}

$vc_server = $DefaultVIServer | ? { $_.Name -eq $vCenter};
$disconnect = $false;

if ($vc_server -eq $null) {
	if ($Credential -ne $null) {
		$vc_server = Connect-VIServer -Server $vCenter -Credential $Credential;
	} else {
		$vc_server = Connect-VIServer -Server $vCenter;
	}
	
	if ($vc_server -ne $null) {
		Write-Host "Connected to $vCenter";	
		$disconnect = $true;
	}
	
} else {
	Write-Host "An existing connection to $vCenter was found and is being used.";
}

if ($vc_server -ne $null) {
	$alarms = Get-AlarmDefinition -Server $vc_server;
	Write-Host "$vCenter has $($alarms.Count) alarms.";
	
	$alarms | % {
		$current_alarm = $_;
		Get-AlarmAction -AlarmDefinition $current_alarm -Server $vc_server | ? { $_.ActionType -eq "SendEmail" } | % {
			$found = $false;
			if ($IncludeAddresses -eq $null -Or $IncludeAddresses.Count -eq 0) {
				$found = $true;
				
			} else {		
				$find_results = $_.To | ? { $IncludeAddresses -contains $_ };
				if ($find_results.Count -gt 0) {
					$found = $true;
				}
			}
		
			if ($found -eq $true) {
				Write-Host "'$($current_alarm.Name)' (defined in '$((Get-View $current_alarm.ExtensionData.Info.Entity).Name)' is being sent to $($_.To)";
			}
		}
	}
}

if ($disconnect -eq $true) {
	Disconnect-VIServer $vc_server;
}