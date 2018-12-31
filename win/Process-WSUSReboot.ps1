# Ensure we have a Scripts Folder.
if ((Test-Path "c:\Scripts") -eq $False) {
	New-Item -Name "C:\Scripts" -Type Directory | out-null;
}

# Remove any previous files.
if ((Test-Path "c:\scripts\reboot-task.txt") -eq $True) { Remove-Item "c:\scripts\reboot-task.txt"; }

$result = (get-item "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -EA Ignore -EV a);
if ($a -ne $null) {
	# There was an error.
	Set-Content -Path "c:\scripts\reboot-task.txt" -Value $a;
	
} else {
	# No error - process the result.
	if ($result -ne $null) {
		# Reboot.
		$out = "Rebooting the Operating System."
		$out | Set-Content -Path "c:\scripts\reboot-task.txt"
		Restart-Computer -Confirm:$False -Force;
		
	} else {
		$out = "No updates require the OS to be restarted.";
		$out | Set-Content -Path "c:\scripts\reboot-task.txt";

	}
}
