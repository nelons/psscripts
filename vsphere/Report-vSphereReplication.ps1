Param([Parameter(Mandatory=$true)] $VMName,
      [DateTime] $Start,
      [DateTime] $Finish,
      [string] $OutputFile);

$vm = Get-VM $VMName;
if ($null -ne $vm) {
    $EventStart = $null;
    if ($null -eq $Start) {
        $EventStart = $(Get-Date).AddDays(-7);
    } else {
        Write-Host $Start.ToString();
        $EventStart = $Start;
    }

    $EventEnd = $null;
    if ($null -eq $Finish) {
        $EventEnd = Get-Date;
    } else {
        Write-Host $Finish.ToString();
        $EventEnd = $EventEnd;
    }

    $events = get-vievent -MaxSamples ([int]::MaxValue) -Start $EventStart -Finish $EventEnd | ? { $_.EventTypeId -eq "hbr.primary.DeltaCompletedEvent" } | Select CreatedTime, @{L="MB Transferred";E={ [math]::Round($_.Arguments.Value/1MB, 2)}}
    if ($null -ne $events) {
        if ($null -ne $OutputFile -And $OutputFile.Length -gt 0) {
            $events | Export-Csv -NoTypeInformation -Path $OutputFile;
        } else {
            $events;
        }
    } else {
        Write-Host "Could not find any replication events for the vm $VMName" -Foreground Red;
    }

} else {
    Write-Host "Could not find a VM with the name $VMName" -Foreground Red;
}