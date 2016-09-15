param([Parameter(Mandatory=$true)][string] $vCenter,
      [System.Management.Automation.PSCredential] $Credential,
	  [Parameter(Mandatory=$true)][string] $CurrentEmailAddress,
	  [Parameter(Mandatory=$true)][string] $NewEmailAddress,
	  [switch] $WhatIf = $False)
	  
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
		$actions = Get-AlarmAction -AlarmDefinition $current_alarm -Server $vc_server | ? { $_.ActionType -eq "SendEmail" };
		if ($actions -ne $null) {		
			#Write-Host "Alarm '$($current_alarm.Name)' has $($actions.Count) actions to send an email";
			$actions | % {
				if ($_.To -eq $CurrentEmailAddress) {
					Write-Host "The alarm '$($current_alarm.Name)' was being sent to '$CurrentEmailAddress' and has been changed to '$NewEmailAddress'";
					$aa = New-AlarmAction -AlarmDefinition $current_alarm -Email -Subject $_.Subject -To $NewEmailAddress -Cc $_.Cc -Body $_.Body -Server $vc_server -WhatIf:$WhatIf;
					$def_trigger = $aa.Trigger;
					$def_trigger_action = 1;
					# def_trigger should either be unchanged (0), removed (1), or repeat changed (2).
					# default action is to remove, we will change this if we find it in the list of alarm actions we are copying.
					
					# There must always be a trigger on the alarm action, so cannot remove all and then add. Must add and then remove.										
					$triggers = Get-AlarmActionTrigger -AlarmAction $_ | % {						
						if ($_.StartStatus -ne $def_trigger.StartStatus -Or $_.EndStatus -ne $def_trigger.EndStatus) {
							# Create all the other triggers.
							New-AlarmActionTrigger -AlarmAction $aa -StartStatus $_.StartStatus -EndStatus $_.EndStatus -Repeat:$_.Repeat -WhatIf:$WhatIf
							
						} else {
							# This is the default trigger.
							if ($_.Repeat -eq $def_trigger.Repeat) {
								# Do nothing, this action is identical to the default one.
								$def_trigger_action = 0;
								
							} else {
								# We need to change the repeat.
								$def_trigger_action = 2;
							}							
						}				
					};
					
					# Do something to the default trigger.
					$triggers = Get-AlarmActionTrigger $aa;
					if ($def_trigger_action -eq 1) {
						if ($triggers.Count -gt 1) {
							Remove-AlarmActionTrigger -AlarmActionTrigger $def_trigger -Confirm:$false -WhatIf:$WhatIf;
							
						} else {
							Write-Warning "Alarm '$($current_alarm.Name)' wants to have no triggers on it's 'SendEmail' action, but this cannot be set using PowerCLI.";
						}
					
					} elseif ($def_trigger_action -eq 2) {
						$temp_trigger = $null;
						if ($triggers.Count -eq 1) {						
							# We need to add a temp trigger in here, remove the default and then re-add it.
							if ($def_trigger.StartStatus -eq "Green") {
								# Handles green->yellow trigger.
								$temp_trigger = New-AlarmActionTrigger -AlarmAction $aa -StartStatus Red -EndStatus Yellow;
								
							} else {
								# Handles yellow->red, yellow->green and red->yellow triggers.
								$temp_trigger = New-AlarmActionTrigger -AlarmAction $aa -StartStatus Green -EndStatus Yellow;
							
							}
						}
													
						# We can just remove the default trigger
						Remove-AlarmActionTrigger -AlarmActionTrigger $def_trigger -Confirm:$false -WhatIf:$WhatIf;
							
						# And re-add.
						$def_not_repeat = !($def_trigger.Repeat);
						New-AlarmActionTrigger -AlarmAction $aa -StartStatus $def_trigger.StartStatus -EndStatus $def_trigger.EndStatus -Repeat:$def_not_repeat -WhatIf:$WhatIf | out-null;
						
						if ($temp_trigger -ne $null) {
							Remove-AlarmActionTrigger $temp_trigger -Confirm:$false;
							
						}
					}
					
					Remove-AlarmAction -AlarmAction $_ -Confirm:$False -WhatIf:$WhatIf;
				}
			}
		}
	}
	
	Write-Host "Finished checking alarms."

	if ($disconnect -eq $true) {
		Disconnect-VIServer $vc_server -Confirm:$False;
		Write-Host "Disconnected from $vCenter";	
	}
}