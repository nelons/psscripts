param([string[]] $Community = { "public", "private" },
      [string] $NetworkRange = "",
      [string] $NetworkStart = "",
      [string] $NetworkEnd = "",
      [switch] $InstallModules = $false)

# Test for IP calculation module
$module = Get-Module -Name Indented.Net.IP;
if ($null -eq $module) {
    if ($InstallModules -eq $true) {
        Install-Module -Name Indented.Net.IP -Confirm:$false;

    }
    
    if ($(Get-Module -Name Indented.Net.IP) -eq $false) {
        Write-Host "The 'Indented.Net.IP' module needs to be installed for this script to work.";
        Write-Host "Run 'Install-Module -Name Indented.Net.IP' to install it."
        exit;
    }
}

# Get the SNMP module
$module = Get-Module -Name SNMP
if ($null -eq $module) {
    if ($InstallModules -eq $true) {
        Install-Module -Name SNMP -Confirm:$false;

    }
    
    if ($(Get-Module -Name SNMP) -eq $false) {
        Write-Host "The 'SNMP' module needs to be installed for this script to work.";
        Write-Host "Run 'Install-Module -Name SNMP' to install it."
        exit;
    }
}

$snmp_results = @();

$network_addresses = @();

if ($NetworkRange -ne $null -And $NetworkRange.Length -gt 0) {
    $network_addresses = Get-NetworkRange -IPAddress $NetworkRange | Select-Object -expandproperty IPAddressToString

} elseif ($NetworkStart -ne $null -And $NetworkStart.Length -gt 0 -And $NetworkEnd -ne $null -And $NetworkEnd.Length -gt 0) {
    $network_addresses = Get-NetworkRange -Start $NetworkStart -End $NetworkEnd | Select-Object -expandproperty IPAddressToString

} else {
    Write-Host "You need to specify either the -NetworkRange in IP/CIDR format (e.g. 192.168.0.0/24) or both a -NetworkStart/-NetworkEnd address." -ForegroundColor Red;
    exit;
}

if ($($network_addresses.Count) -eq 0) {
    Write-Host "No network addresses could be calculated for scanning.";
    exit;
}

$current_progress = 0;
$pc_increase = 100 / ($network_addresses.count * $Community.Count);

$network_addresses | ForEach-Object { 
    $ip = $_;

    $Endpoint = New-Object -TypeName psobject;
    $Endpoint | Add-Member -NotePropertyName "IP" -NotePropertyValue $ip;

    $dns_result = Resolve-DnsName $ip -ErrorAction SilentlyContinue;
    if ($null -ne $dns_result -And $dns_result.Count -eq 1) {
        $dns_name = $dns_result.NameHost;
        $Endpoint | Add-Member -NotePropertyName "DNS" -NotePropertyValue $dns_name;
    } 

    $Community | ForEach-Object {
        $snmp_result = $null;
        try {
            $snmp_result = Get-SnmpData -IP $ip -Community $_ -OID 1.3 -Version V2 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue;
            
        } catch {
            $snmp_result = $null;

        }

        # TODO(neale): Add the result for this community to the object.
        $PropertyName = "Community-$_";
        $PropertyValue = ($null -ne $snmp_result);

        $Endpoint | Add-Member -NotePropertyName $PropertyName -NotePropertyValue $PropertyValue

        $current_op = "$($Endpoint.IP) - $_";

        #$current_progress = [math]::floor($current_progress + $pc_increase);
        $current_progress += $pc_increase;
        $rational_progress = [math]::Floor($current_progress);
        Write-Progress -Activity "Scanning IPs for SNMP communities" -Status "Running" -CurrentOperation $current_op -PercentComplete $rational_progress;
    }

    $snmp_results += $Endpoint;
}

Write-Progress -Activity "Scanning IPs for SNMP communities" -Completed;

return $snmp_results;
