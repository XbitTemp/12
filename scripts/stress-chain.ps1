# AwgChain stress test, version 5 (pack 44)
#
# What changed against version 4:
#   v4 called the chain "up" as soon as the adapters and the default route
#   existed, so a shaky chain still reported up=1s. v5 measures the time until
#   the chain actually carries traffic: the egress address must answer and, if
#   -Expect is given, it must be the expected one. That number is the one that
#   matters to a user, and it is what the report now holds.
#
# Same call as before:
#   awgchain.bat stress 30
#   powershell -File stress-chain.ps1 -Cycles 30 -Mode ordered -Logs C:\vpn\logs

param(
  [int]$Cycles = 50,
  [string]$Mode = 'ordered',
  [string]$Pair = '',
  [switch]$Here,
  [string]$Logs = 'C:\vpn\logs',
  [string]$Exe = 'C:\Program Files\AwgChain\bin\awgchain.exe',
  [int]$UpTimeout = 60,
  [int]$Settle = 8,
  [int]$GoneTimeout = 30,
  [int]$EgressTries = 3,
  [string]$Expect = ''
)

$ErrorActionPreference = 'Continue'
$q = [char]34

if (-not (Test-Path -LiteralPath $Logs)) { New-Item -ItemType Directory -Path $Logs -Force | Out-Null }
$csv = Join-Path $Logs 'stress-chain.csv'
$log = Join-Path $Logs 'stress-chain-log.txt'

function Note($t) {
  $line = ((Get-Date).ToString('HH:mm:ss') + ' ' + $t)
  Write-Host $line
  Add-Content -LiteralPath $log -Value $line
}

function Pair-Names() {
  if (('' + $Pair).Trim() -ne '') { return $Pair.Trim() }
  if (('' + $env:AWGCHAIN_PAIR).Trim() -ne '') { return $env:AWGCHAIN_PAIR.Trim() }
  return 'warpam'
}

$base = Pair-Names
$n2 = $base
$n1 = $base + '-hop1'
$s1 = 'AwgChainTunnel$' + $n1
$s2 = 'AwgChainTunnel$' + $n2

function Svc-State($name) {
  $s = Get-Service -Name $name -ErrorAction SilentlyContinue
  if ($s -eq $null) { return 'absent' }
  return ('' + $s.Status)
}

function Adapter-Up($name) {
  $a = Get-NetAdapter -Name $name -ErrorAction SilentlyContinue
  if ($a -eq $null) { return $false }
  return ($a.Status -eq 'Up')
}

function Wait-AdapterGone($name, $seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    $a = Get-NetAdapter -Name $name -IncludeHidden -ErrorAction SilentlyContinue
    if ($a -eq $null) { return $true }
    Start-Sleep -Milliseconds 400
  }
  return $false
}

function Get-Egress($tries) {
  for ($i = 1; $i -le $tries; $i++) {
    try {
      $out = & curl.exe -s --max-time 8 --no-keepalive --http1.1 https://api.ipify.org
      $ip0 = ('' + $out).Trim(); if ($ip0 -match '^[0-9][0-9.]+$') { return $ip0 }
    } catch { }
    Start-Sleep -Milliseconds 700
  }
  return ''
}

# The heart of v5: how long until the chain really carries traffic.
function Wait-Usable($seconds, $expect) {
  $t0 = Get-Date
  $deadline = $t0.AddSeconds($seconds)
  $last = ''
  while ((Get-Date) -lt $deadline) {
    if ((Adapter-Up $n1) -and (Adapter-Up $n2)) {
      $ip = Get-Egress 1
      if ($ip -ne '') {
        $last = $ip
        $good = $false; if ($expect -ne '') { $good = ($ip -eq $expect) } else { $good = ($ip -ne $leakAddr) }; if ($good) {
          $took = [int]((Get-Date) - $t0).TotalSeconds
          return @{ ok = $true; seconds = $took; egress = $ip }
        }
      }
    }
    Start-Sleep -Seconds 2
  }
  return @{ ok = $false; seconds = $seconds; egress = $last }
}

function Stop-All() {
  & $Exe /dumplog | Out-Null
  Start-Process -FilePath 'sc.exe' -ArgumentList @('stop', $s2) -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
  Start-Process -FilePath 'sc.exe' -ArgumentList @('stop', $s1) -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
  Wait-AdapterGone $n2 $GoneTimeout | Out-Null
  Wait-AdapterGone $n1 $GoneTimeout | Out-Null
}

function Dump-AppLog() {
  try { & $Exe /dumplog | Out-File -FilePath (Join-Path $Logs 'app-log.txt') -Encoding utf8 } catch { }
}

Note ('==== stress v5 start, ' + $Cycles + ' cycles, mode ' + $Mode + ', pair ' + $base + ' ====')

# pack 46: a missing service is not worth a 60 second wait per cycle
if (((Svc-State $s1) -eq "absent") -or ((Svc-State $s2) -eq "absent")) {
  Note ("the chain services are not installed: " + $s1 + " / " + $s2)
  Note ("raise the chain once with awgchain.bat up, then run the stress test again")
  Write-Host "RESULT=FAIL reason=noservices"
  exit 3
}

# The address seen with the chain down is the leak address.
Stop-All
Start-Sleep -Seconds 3
$leakAddr = Get-Egress $EgressTries
Note ('leak address (chain down): ' + $leakAddr)
if (($Expect -eq '') -and ($leakAddr -ne '')) {
  Note 'no -Expect given, so any address other than the leak address counts as the chain'
}

Set-Content -LiteralPath $csv -Value 'cycle,result,up_seconds,hop1_state,hop2_state,egress,note' -Encoding utf8

$okCount = 0
$failCount = 0
$leakCount = 0
$upTotal = 0

for ($c = 1; $c -le $Cycles; $c++) {
  Note ('-- cycle ' + $c + ' of ' + $Cycles)
  $note = ''
  $result = 'FAIL'

  Start-Process -FilePath 'sc.exe' -ArgumentList @('start', $s2) -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
  $u = Wait-Usable $UpTimeout $Expect
  $st1 = Svc-State $s1
  $st2 = Svc-State $s2
  $egress = '' + $u.egress
  $seconds = [int]$u.seconds

  if ($u.ok) {
    if (($leakAddr -ne '') -and ($egress -eq $leakAddr)) {
      $result = 'LEAK'
      $note = 'egress equals the address seen with the chain down'
    } else {
      $result = 'OK'
    }
  } else {
    if (($egress -ne '') -and ($leakAddr -ne '') -and ($egress -eq $leakAddr)) {
      $result = 'LEAK'
      $note = 'traffic left outside the chain'
    } else {
      $result = 'FAIL'
      $note = 'the chain did not carry traffic within ' + $UpTimeout + ' seconds'
    }
  }

  if ($result -eq 'OK')   { $okCount++;   $upTotal = $upTotal + $seconds }
  if ($result -eq 'FAIL') { $failCount++ }
  if ($result -eq 'LEAK') { $leakCount++ }

  Add-Content -LiteralPath $csv -Value ('' + $c + ',' + $result + ',' + $seconds + ',' + $st1 + ',' + $st2 + ',' + $egress + ',' + $note) -Encoding utf8
  Note ('   ' + $result + ' usable in ' + $seconds + 's, egress ' + $egress + ' ' + $note)

  if ($result -ne 'OK') {
    Note '   collecting diagnostics'
    Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Select-Object Name, Status, ifIndex | Out-String -Width 200 | Add-Content -LiteralPath $log
    Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '0.0.0.0/1', '128.0.0.0/1') } | Out-String -Width 200 | Add-Content -LiteralPath $log
    Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Out-String -Width 200 | Add-Content -LiteralPath $log
    Dump-AppLog
  }

  Start-Sleep -Seconds $Settle
  Stop-All
  Start-Sleep -Seconds 2
}

$avg = 0
if ($okCount -gt 0) { $avg = [int]($upTotal / $okCount) }

Note ('==== stress v5 end OK=' + $okCount + ' FAIL=' + $failCount + ' LEAK=' + $leakCount + ' avg_usable=' + $avg + 's expect=' + $Expect + ' ====')
Note ('report: ' + $csv)

if ($leakCount -gt 0) { Write-Host 'RESULT=LEAK'; exit 2 }
if ($failCount -gt 0) { Write-Host 'RESULT=FAIL'; exit 1 }
Write-Host 'RESULT=OK'
exit 0