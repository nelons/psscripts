#
# Abridged version of:
# https://github.com/Prakash82x/PowerShell/blob/master/TerminalService/Reset-TSGracePeriod.ps1
#
# Ideal for running as a scheduled task with the command line:
# powershell -ExecutionPolicy Bypass -File <Full path to file>
#

#Start-Transcript -Path "C:\scripts\Reset-TerminalServicesGracePeriod.txt";

$definition = @"
using System;
using System.Runtime.InteropServices; 
namespace Win32Api
{
	public class NtDll
	{
		[DllImport("ntdll.dll", EntryPoint="RtlAdjustPrivilege")]
		public static extern int RtlAdjustPrivilege(ulong Privilege, bool Enable, bool CurrentThread, ref bool Enabled);
	}
}
"@ 

Add-Type -TypeDefinition $definition -PassThru

$bEnabled = $false

## Enable SeTakeOwnershipPrivilege
$res = [Win32Api.NtDll]::RtlAdjustPrivilege(9, $true, $false, [ref]$bEnabled)

## Take Ownership on the Key
$key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\RCM\\GracePeriod", [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::TakeOwnership)
$acl = $key.GetAccessControl()
$acl.SetOwner([System.Security.Principal.NTAccount]"Administrators")
$key.SetAccessControl($acl)

## Assign Full Controll permissions to Administrators on the key.
$rule = New-Object System.Security.AccessControl.RegistryAccessRule ("Administrators","FullControl","Allow")
$acl.SetAccessRule($rule)
$key.SetAccessControl($acl)

## Finally Delete the key which resets the Grace Period counter to 120 Days.
Remove-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\GracePeriod'

Restart-Service -Name TermService -Force

#Stop-Transcript;
