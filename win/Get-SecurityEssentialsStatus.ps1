Function BinaryToDate {
    Param($Value)
    Process {
        $int64value = [System.BitConverter]::ToInt64($Value, 0);
        $date = [datetime]::FromFileTime($int64value);
        return $date;
    }
}

$key_path = "";
$av_type = "";
$mse_path = "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft Antimalware";
$defender_path = "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows Defender";
$app_name = "msmpeng.exe"

if ($(Test-Path $mse_path) -eq $true) {
    $key_path = $mse_path;
    $av_type = "Microsoft Security Essentials";
    
} elseif ($(Test-Path $defender_path) -eq $true) {
    $key_path = $defender_path;
    $av_type = "Windows Defender";

} else {
    Write-Host "Could not find an appropriate product on the computer." -ForegroundColor Red;
    exit;
}

$scan_path = "$key_path\Scan";
$signature_path = "$key_path\Signature Updates";

$av_version_value = "AVSignatureVersion";
$av_applied_value = "AVSignatureApplied";
$as_version_value = "ASSignatureVersion";
$as_applied_value = "ASSignatureApplied";
$engine_version_value = "EngineVersion"
$last_scan_value = "LastScanRun";

$av_version = (Get-ItemProperty -Path $signature_path -Name $av_version_value).AVSignatureVersion;
$av_applied = BinaryToDate -value $((Get-ItemProperty -Path $signature_path -Name $av_applied_value).AVSignatureApplied);
$as_version = (Get-ItemProperty -Path $signature_path -Name $as_version_value).ASSignatureVersion;
$as_applied = BinaryToDate -value $((Get-ItemProperty -Path $signature_path -Name $as_applied_value).ASSignatureApplied);
$engine_version = (Get-ItemProperty -Path $signature_path -Name $engine_version_value).EngineVersion;
$last_scan = BinaryToDate -value $((Get-ItemProperty -Path $scan_path -Name $last_scan_value).LastScanRun);

Write-Host "AV Status" -ForegroundColor Green;
Write-Host "AV Type: $av_type";

$product_version = "";
$install_location = (Get-ItemProperty -Path $key_path -Name "InstallLocation").InstallLocation;
$file = Get-Item -Path "$install_location\$app_name";
if ($null -ne $file) {
    $product_version = [Version](($file.VersionInfo.FileMajorPart, $file.VersionInfo.FileMinorPart, $file.VersionInfo.FileBuildPart, $file.VersionInfo.FilePrivatePart) -join ".");
    Write-Host "Product Version: $product_version";
} else {
    Write-Host "Could not retrieve product version." -ForegroundColor Red
}

Write-Host "Engine Version: $engine_version";
Write-Host "AV Signature Version: $av_version";
Write-Host "AV Signatures Applied: $($av_applied.ToString())"; 
Write-Host "AS Signature Version: $as_version";
Write-Host "AS Signatures Applied: $($as_applied.ToString())";
Write-Host "Last Scan Time: $($last_scan.ToString())";

$info = "" | Select AVType, ProductVersion, EngineVersion, AVSignatureVersion, AVSignatureApplied, ASSignatureVersion, ASSignatureApplied, LastScanTime;
$info.AVType = $av_type;
$info.ProductVersion = $product_version.ToString();
$info.EngineVersion = $engine_version;
$info.AVSignatureVersion = $av_version;
$info.AVSignatureApplied = $av_applied.ToString();
$info.ASSignatureVersion = $as_version;
$info.ASSignatureApplied = $as_applied.ToString();
$info.LastScanTime = $last_scan.ToString();

<#
if ($(Test-Path "C:\OIAdmin") -eq $false) {
    # Create the folder.
    New-Item -Type Directory -Path "C:\" -Name "OIAdmin" | out-null;
    $f = Get-Item "C:\OIAdmin";
    $f.Attributes = "Hidden";
}

# Save out to file.
$json_support = Get-Command "ConvertTo-JSON" -ErrorAction SilentlyContinue;
if ($null -ne $json_support) {
    $json = $info | ConvertTo-Json;
    $json | Set-Content "C:\OIAdmin\av_status.json";
    Write-Host "Information written in JSON format." -ForegroundColor Green;
}
#>

return $info;