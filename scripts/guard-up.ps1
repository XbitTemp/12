param(
  [int]$Timeout = 180,
  [switch]$Persist,
  [string]$Bin = 'C:\Program Files\AwgChain\bin',
  [string]$Data = 'C:\Program Files\AwgChain\Data',
  [string]$Hop1 = 'hop1-warp',
  [string]$Hop2 = 'hop2-amnezia',
  [string]$LogDir = '',
  [switch]$NoLan,
  [switch]$DryRunOnly
)

$ErrorActionPreference = 'Continue'

function Clean-Path([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return '' }
  $p = $p.Trim()
  $p = $p.Trim('"')
  while ($p.EndsWith('\')) { $p = $p.Substring(0, $p.Length - 1) }
  return $p
}

# Start-Process in PowerShell 5.1 does not quote arguments that contain
# spaces, so every argument is quoted by hand and passed as one string.
function Q([string]$s) {
  return ('"' + $s + '"')
}

function Show-File([string]$title, [string]$path) {
  Write-Output ("--- " + $title + " ---")
  if ([string]::IsNullOrWhiteSpace($path)) { Write-Output '(no path)'; return }
  if (-not (Test-Path -LiteralPath $path)) { Write-Output '(file was not created)'; return }
  $txt = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($txt)) { Write-Output '(empty)' } else { Write-Output $txt.TrimEnd() }
}

function Get-ConfValue([string]$file, [string]$key) {
  if (-not (Test-Path -LiteralPath $file)) { return '' }
  foreach ($line in Get-Content -LiteralPath $file) {
    $t = $line.Trim()
    if ($t.StartsWith('#') -or $t.StartsWith(';')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $k = $t.Substring(0, $i).Trim()
    if ($k -ieq $key) { return $t.Substring($i + 1).Trim() }
  }
  return ''
}

function Resolve-Endpoint([string]$ep) {
  if ([string]::IsNullOrWhiteSpace($ep)) { return '' }
  $h = $ep
  $port = ''
  $i = $ep.LastIndexOf(':')
  if ($i -gt 0) {
    $h = $ep.Substring(0, $i)
    $port = $ep.Substring($i + 1)
  }
  $h = $h.Trim('[', ']')
  $ip = $h
  $parsed = [System.Net.IPAddress]::Any
  if (-not [System.Net.IPAddress]::TryParse($h, [ref]$parsed)) {
    try {
      $a = [System.Net.Dns]::GetHostAddresses($h) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
      if ($a) { $ip = $a.IPAddressToString }
    } catch { return '' }
  }
  if ($port -ne '') { return ($ip + ':' + $port) }
  return $ip
}

function Get-PhysicalPrefixes([string]$a, [string]$b) {
  $out = @()
  try { $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop } catch { return $out }
  foreach ($ad in $addrs) {
    if ($ad.PrefixLength -ge 32) { continue }
    if ($ad.IPAddress -like '127.*') { continue }
    if ($ad.IPAddress -like '169.254.*') { continue }
    $alias = [string]$ad.InterfaceAlias
    if ($alias -eq $a -or $alias -eq $b) { continue }
    $nic = Get-NetAdapter -InterfaceIndex $ad.InterfaceIndex -ErrorAction SilentlyContinue
    if ($nic) {
      if ($nic.Status -ne 'Up') { continue }
      if ([string]$nic.InterfaceDescription -match 'Wintun|WireGuard|TAP|VPN|Loopback') { continue }
    }
    $parts = $ad.IPAddress.Split('.')
    if ($parts.Count -ne 4) { continue }
    $bits = [int]$ad.PrefixLength
    $mask = if ($bits -eq 0) { 0 } else { [uint32]((0xFFFFFFFFL -shl (32 - $bits)) -band 0xFFFFFFFFL) }
    $val = ([uint32]$parts[0] -shl 24) -bor ([uint32]$parts[1] -shl 16) -bor ([uint32]$parts[2] -shl 8) -bor [uint32]$parts[3]
    $net = $val -band $mask
    $netStr = ('{0}.{1}.{2}.{3}' -f (($net -shr 24) -band 255), (($net -shr 16) -band 255), (($net -shr 8) -band 255), ($net -band 255))
    $cidr = $netStr + '/' + $bits
    if ($out -notcontains $cidr) { $out += $cidr }
  }
  return $out
}

Write-Output '=== AwgChain kill switch: start ==='
Write-Output ("date  : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

$Bin = Clean-Path $Bin
$Data = Clean-Path $Data
$LogDir = Clean-Path $LogDir
if ([string]::IsNullOrWhiteSpace($LogDir)) { $LogDir = Join-Path $env:TEMP 'AwgChainLogs' }
if (-not (Test-Path -LiteralPath $LogDir)) {
  New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
Write-Output ("logs  : " + $LogDir)

$guardExe = Join-Path $Bin 'awgchain-guard.exe'
$clientExe = Join-Path $Bin 'awgchain.exe'
if (-not (Test-Path -LiteralPath $guardExe)) {
  Write-Output 'GUARD=FAIL'
  Write-Output ("reason: guard binary not found at " + $guardExe)
  Write-Output 'hint  : run  awgchain.bat build'
  exit 1
}
$gi = Get-Item -LiteralPath $guardExe
Write-Output ("guard : " + $guardExe)
Write-Output ("size  : " + $gi.Length + "  built: " + $gi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))

$conf1 = Join-Path $Data ('Configurations\' + $Hop1 + '.conf')
$conf2 = Join-Path $Data ('Configurations\' + $Hop2 + '.conf')
foreach ($c in @($conf1, $conf2)) {
  if (-not (Test-Path -LiteralPath $c)) {
    Write-Output 'GUARD=FAIL'
    Write-Output ("reason: config not found: " + $c)
    exit 1
  }
}

$ep1 = Resolve-Endpoint (Get-ConfValue $conf1 'Endpoint')
$ep2 = Resolve-Endpoint (Get-ConfValue $conf2 'Endpoint')
if ($ep1 -eq '' -or $ep2 -eq '') {
  Write-Output 'GUARD=FAIL'
  Write-Output 'reason: could not resolve hop endpoints from the configs'
  exit 1
}

$dnsRaw = Get-ConfValue $conf2 'DNS'
$dnsList = @()
foreach ($d in $dnsRaw.Split(',')) {
  $d = $d.Trim()
  if ($d -ne '' -and $d -notmatch '[A-Za-z]') { $dnsList += $d }
}
if ($dnsList.Count -eq 0) { $dnsList = @('1.1.1.1', '1.0.0.1') }
$dns = [string]::Join(',', $dnsList)

$lan = ''
if (-not $NoLan) {
  $prefixes = Get-PhysicalPrefixes $Hop1 $Hop2
  if ($prefixes.Count -gt 0) { $lan = [string]::Join(',', $prefixes) }
}

$appList = @()
if (Test-Path -LiteralPath $clientExe) { $appList += $clientExe }

Write-Output ("HOP1EP=" + $ep1)
Write-Output ("HOP2EP=" + $ep2)
Write-Output ("DNS=" + $dns)
Write-Output ("LAN=" + $lan)
Write-Output ("APPS=" + [string]::Join(';', $appList))
# The guard converts its timeout into milliseconds for WaitForSingleObject,
# so a week is the largest value that is comfortably safe there.
if ($Persist -or $Timeout -le 0) {
  $Timeout = 604800
  Write-Output 'MODE=PERSISTENT'
  Write-Output 'The lock will hold for 7 days, or until:  awgchain.bat ks off'
} else {
  Write-Output 'MODE=TIMED'
}
Write-Output ("TIMEOUT=" + $Timeout)

$base = '-hop1if ' + (Q $Hop1) + ' -hop2if ' + (Q $Hop2) + ' -hop1ep ' + (Q $ep1) + ' -hop2ep ' + (Q $ep2) + ' -dns ' + (Q $dns)
if ($lan -ne '') { $base += ' -lan ' + (Q $lan) }
foreach ($app in $appList) { $base += ' -allowapp ' + (Q $app) }

$preOut = Join-Path $LogDir 'guard-dryrun.txt'
$preStd = Join-Path $LogDir 'guard-dryrun-stdout.txt'
$preErr = Join-Path $LogDir 'guard-dryrun-stderr.txt'
$guardOut = Join-Path $LogDir 'guard-log.txt'
$guardStd = Join-Path $LogDir 'guard-stdout.txt'
$guardErr = Join-Path $LogDir 'guard-stderr.txt'
foreach ($f in @($preOut, $preStd, $preErr, $guardOut, $guardStd, $guardErr)) {
  if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

Write-Output '--- preflight (dry run) ---'
$preLine = $base + ' -dryrun -logfile ' + (Q $preOut)
Write-Output ("cmdline: " + (Q $guardExe) + ' ' + $preLine)

$pre = $null
try {
  $pre = Start-Process -FilePath $guardExe -ArgumentList $preLine -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $preStd -RedirectStandardError $preErr
} catch {
  Write-Output 'GUARD=FAIL'
  Write-Output ("reason: could not start the guard: " + $_.Exception.Message)
  exit 1
}

Show-File 'dry run stdout' $preStd
Show-File 'dry run stderr' $preErr

$preText = ''
foreach ($f in @($preStd, $preOut)) {
  if (Test-Path -LiteralPath $f) {
    $preText += (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue)
  }
}

if ($pre.ExitCode -ne 0 -or $preText -notmatch 'KILLSWITCH=DRYRUN') {
  Write-Output 'GUARD=FAIL'
  Write-Output ("reason: preflight failed, exit code " + $pre.ExitCode)
  Write-Output 'note  : no firewall filters were installed'
  exit 1
}
Write-Output 'PREFLIGHT=OK'

if ($DryRunOnly) {
  Write-Output 'GUARD=DRYRUN'
  Write-Output 'Nothing was installed. Arm the real lock with:  awgchain.bat ks on 180'
  exit 0
}

Write-Output '--- starting the guard ---'
$runLine = $base + ' -timeout ' + [string]$Timeout + ' -logfile ' + (Q $guardOut)
Write-Output ("cmdline: " + (Q $guardExe) + ' ' + $runLine)

$proc = $null
try {
  $proc = Start-Process -FilePath $guardExe -ArgumentList $runLine -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $guardStd -RedirectStandardError $guardErr
} catch {
  Write-Output 'GUARD=FAIL'
  Write-Output ("reason: could not start the guard: " + $_.Exception.Message)
  exit 1
}

Start-Sleep -Seconds 4
$alive = $false
try { $alive = -not $proc.HasExited } catch { $alive = $false }

Show-File 'guard stdout' $guardStd
Show-File 'guard stderr' $guardErr
Show-File 'guard log' $guardOut

$runText = ''
foreach ($f in @($guardStd, $guardOut)) {
  if (Test-Path -LiteralPath $f) {
    $runText += (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue)
  }
}

if (-not $alive) {
  Write-Output 'GUARD=FAIL reason=guard-exited'
  Write-Output ("exit code: " + $proc.ExitCode)
  Write-Output 'note  : the guard uses a dynamic WFP session, so its filters died with it'
  exit 1
}
if ($runText -notmatch 'KILLSWITCH=OK') {
  Write-Output 'GUARD=FAIL reason=no-ok-marker'
  Write-Output ("pid   : " + $proc.Id)
  Write-Output 'hint  : stop it with  awgchain.bat ks off'
  exit 1
}

Write-Output ("GUARD=UP pid=" + $proc.Id)
Write-Output ("The kill switch will release itself in " + $Timeout + " seconds.")
Write-Output 'To release it earlier:  awgchain.bat ks off'
exit 0
