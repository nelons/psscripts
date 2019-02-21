param([Parameter(Mandatory=$true)][string] $GroupName = $(Read-Host -Prompt "Please enter a group name"),
      [string[]] $Add = $(Read-Host -Prompt "(optional) Please enter the names of any users to add to the group"),
      [string[]] $Remove = $(Read-Host -Prompt "(optional) Please enter the names of any users to remove from the group"),
      [Parameter(Mandatory=$true)][string] $RemoteDomainName = $(Read-Host -Prompt "Please enter the remote domain name"),
      [Parameter(Mandatory=$true)][PSCredential] $RemoteCredential = $(Get-Credential),
      [string] $RemoteDC,
      [switch] $Confirm)

# Ensure that this is loaded. Fail if not.
if ($null -eq $(Get-Module ActiveDirectory)) {
	Write-Host "Attempting to load ActiveDirectory module.";
	try {
		Import-Module ActiveDirectory;
		Write-Host "Loaded ActiveDirectory module." -ForegroundColor Green;
	} catch {
		Write-Host "Could not load ActiveDirectory module" -Foreground Red;
		exit;
	}
}

# Try and connect to the remote domain.
$domain = Get-ADDomain $RemoteDomainName -Credential $RemoteCredential -ErrorAction SilentlyContinue;
if ($null -eq $domain) {
    Write-Host "There was an error retrieving domain information for $RemoteDomainName" -ForegroundColor Red;
    exit;
}

# Get the group in the local domain.
$group = Get-ADGroup $GroupName -ErrorAction SilentlyContinue -Properties *
if ($null -eq $group) {
    exit;
}

if ($group.GroupScope -ne "DomainLocal") {
    Write-Host "The group $($group.Name) has scope $($group.GroupScope)";
    Write-Host "The group is not configured to contain remote users." -ForegroundColor Red;
    exit;
}

# Get the remote domain details.
$RemoteNetBIOS = $domain.NetBIOSName;
$RemoteDN = "//RootDSE/$($domain.DistinguishedName)";

if ($null -eq $RemoteDC -Or $RemoteDC.Length -eq 0) {
    $dc = Get-ADDomainController -Discover -DomainName $RemoteNetBIOS
    $RemoteDC = $dc.HostName;
}

# Try and map the remote domain to a PS drive.
try {
    New-PSDrive -Name $RemoteNetBIOS -Credential $RemoteCredential -Root $RemoteDN -PSProvider ActiveDirectory -Server $RemoteDC | out-null

} catch {
    Write-Host "There was an error connecting to the $RemoteDomainName domain." -ForegroundColor Red;
    exit;
}

foreach ($username in $Add) {
    if ($null -eq $username -Or $username.Length -eq 0) {
        continue;
    }

    # Get the user and add to the group.
    $user = Get-ADUser -Filter {SamAccountName -eq $username} -Server $RemoteNetBIOS -Credential $RemoteCredential;
    if ($null -ne $user) {           
        $group | Add-ADGroupMember -Members $user;
        Write-Host "$username was added to the group '$GroupName' successfully." -ForegroundColor Green;

    } else {
        Write-Host "Could not find a user with the username '$username'" -ForegroundColor Red;

    }
}

foreach ($username in $Remove) {
    if ($null -eq $username -Or $username.Length -eq 0) {
        continue;
    }

    $user = Get-ADUser -Filter {SamAccountName -eq $username} -Server $RemoteNetBIOS -Credential $RemoteCredential;
    if ($null -ne $user) {
        Remove-ADPrincipalGroupMembership -Server $RemoteNetBIOS -Credential $RemoteCredential $user -MemberOf $group -Confirm:$Confirm;
        Write-Host "$username was successfully removed from the group '$GroupName'" -ForegroundColor Green;

    } else {
        Write-Host "Could not find a user with the username '$username'" -ForegroundColor Red;

    }
}

# Unmap the remote domain
if ($null -ne $(Get-PSDrive -Name $RemoteNetBIOS -ErrorAction SilentlyContinue)) {
    Remove-PSDrive $RemoteNetBIOS;
}