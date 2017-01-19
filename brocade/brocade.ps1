Function Get-BrocadeSwitchZoneConfig {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true)][string] $Target,
		[Parameter(Mandatory=$true)][string] $Username,
		[Parameter(Mandatory=$true)][string] $Password,
		[switch] $VersionSix
	)
	Process {
		# Import the SSH-Sessions Module.
		Import-Module $PSScriptRoot\..\modules\SSH-Sessions\SSH-Sessions.psd1
		
		# Connect to the target.
		New-SshSession -ComputerName $Target -Username $Username -Password $Password | out-null
		
		# Invoke the command to get the config.
		$config = "";

		if ($VersionSix -eq $False) {
			$config = Invoke-SshCommand -ComputerName $Target -Command "zoneshow" -Quiet
			
		} else {
			$config = Invoke-SshCommand -ComputerName $Target -Command "bash --login -c 'zoneshow'" -Quiet;
		
		}
	
		# Disconnect from the target.
		Remove-SShSession -ComputerName $Target | out-null;
		
		# return the config.
		return $config;
	}
}

Function Create-FC-Zone {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true)][string] $Hostname,
		[Parameter(Mandatory=$true)][string] $HBA0,
		[Parameter(Mandatory=$true)][string] $HBA1
	)
	Process {
		$brocade_hostname = $Hostname.Replace("-", "");
		$brocade_config_name1 = "config";
		$brocade_config_name2 = "config";
		
		# FC Switch Details.
		$fc_switch1 = "switch1.fqdn";
		$fc_switch2 = "switch2.fqdn";
		$fc_username = "automation";
		$fc_password = "password";
		
		# Proxy Details
		$proxy_host = "proxy.fqdn";
		$proxy_username = "automation";
		$proxy_password = "password";
		
		$config1_ok = $false;
		$config2_ok = $false;

		$config1 = Get-BrocadeSwitchZoneConfig -Target $fc_switch1 -Username $fc_username -Password $fc_password;
		if ($config1.Length -gt 0) {
			$config1_ok = Check-FCConfig -Config $brocade_config_name1 -Hostname $brocade_hostname -HBA $HBA0;
		}

		$config2 = Get-BrocadeSwitchZoneConfig -Target $fc_switch2 -Username $fc_username -Password $fc_password;
		if ($config2.Length -gt 0) {
			$config2_ok = Check-FCConfig -Config $brocade_config_name2 -Hostname $brocade_hostname -HBA $HBA1;
		}

		if ($config1_ok -eq $true -And $config2_ok -eq $true) {			
			# Connect to the brocade scripting host.
			New-SshSession -ComputerName $proxy_host -Username $proxy_username -Password $proxy_password | out-null;
					
			# Run the Script.
			$results = Invoke-SshCommand -ComputerName $proxy_host -Command "./create-fc-zone $fc_switch1 $fc_username $fc_password $brocade_hostname $HBA0 $brocade_config_name" -Quiet;

			# Run the Script.
			$results = Invoke-SshCommand -ComputerName $proxy_host -Command "./create-fc-zone $fc_switch2 $fc_username $fc_password $brocade_hostname $HBA1 $brocade_config_name" -Quiet;
					
			# Disconnect from the host
			Remove-SshSession -ComputerName $proxy_host | out-null;
		}	
    }
}
