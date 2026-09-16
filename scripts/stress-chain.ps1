# AwgChain stress test, version 4 (pack 42).
#
# What changed after the run of 2026-09-16 (50 OK / 0 FAIL, but one earlier
# run showed the flaw):
#   a cycle used to be counted OK as soon as api.ipify.org answered at all.
#   On 2026-09-15 that produced
#       1,OK,81,absent,absent,95.27.119.253,244,hop2 did not come up
#   - the address of the provider, so the traffic went straight out and the
#   test called it a success. Now the egress has to MATCH the exit address of
#   the chain, and the address seen with the chain down is remembered as the
#   leak address: a cycle that shows it is a LEAK, not an OK.
#
#   -Expect 95.182.86.131   pin the expected exit address by hand
#   -Expect ""              (default) the first healthy cycle sets it

param(
  [int]$Cycles = 50,
  [string]$Mode = "ordered",
  [string]$Pair = "",
  [switch]$Here,
  [string]$Logs = "C:\vpn\logs",
  [string]$Exe = "C:\Program Files\AwgChain\bin\awgchain.exe",
  [int]$UpTimeout = 60,
  [int]$Settle = 8,
  [int]$GoneTimeout = 30,
  [int]$EgressTries = 3,
  [string]$Expect = ""
)

$ErrorActionPreference = "SilentlyContinue"

if ($Pair -eq "") {
  $detect = Join-Path $PSScriptRoot "detect-pair.ps1"
  if (Test-Path $detect) { $Pair = (& $detect).Trim() }
}
if ($Pair -eq "") { $Pair = "warpam" }
$hop1 = $Pair + "-hop1"
$svc2 = "AwgChainTunnel$" + $Pair
$svc1 = "AwgChainTunnel$" + $hop1

if (-not (Test-Path $Logs)) { New-Item -ItemType Directory -Path $Logs -Force | Out-Null }
$csv = Join-Path $Logs "stress-chain.csv"
$log = Join-Path $Logs "stress-chain-log.txt"
$applog = Join-Path $Logs "stress-app-log.txt"
"cycle,result,up_seconds,hop1_state,hop2_state,egress,dns_ms,note" | Set-Content -Path $csv -Encoding ASCII
("==== stress start " + (Get-Date) + " pair=" + $Pair + " mode=" + $Mode + " cycles=" + $Cycles) | Set-Content -Path $log -Encoding ASCII
if (Test-Path $applog) { Remove-Item -LiteralPath $applog -Force }

function Svc-State($name) {
  $s = Get-Service -Name $name -ErrorAction SilentlyContinue
  if ($null -eq $s) { return "absent" }
  return $s.Status.ToString()
}

function Wait-Stopped($name, $timeout) {
  $end = (Get-Date).AddSeconds($timeout)
  while ((Get-Date) -lt $end) {
    $st = Svc-State $name
    if ($st -eq "absent" -or $st -eq "Stopped") { return $true }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

# The tunnel service is reported stopped a little before Windows finishes
# tearing the wintun adapter down. Starting the next cycle in that window was
# the thing that produced "hop2 did not come up" out of thin air.
function Wait-AdapterGone($name, $timeout) {
  $end = (Get-Date).AddSeconds($timeout)
  while ((Get-Date) -lt $end) {
    $a = Get-NetAdapter -Name $name -IncludeHidden -ErrorAction SilentlyContinue
    if ($null -eq $a) { return $true }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

function Wait-Adapter($name, $timeout) {
  $end = (Get-Date).AddSeconds($timeout)
  while ((Get-Date) -lt $end) {
    $a = Get-NetAdapter -Name $name -ErrorAction SilentlyContinue
    if ($a -and $a.Status -eq "Up") { return $true }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

function Wait-Route($name, $timeout) {
  # the chain is really usable only when the split default sits on the inner adapter
  $end = (Get-Date).AddSeconds($timeout)
  while ((Get-Date) -lt $end) {
    $r = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.InterfaceAlias -eq $name -and ($_.DestinationPrefix -eq "0.0.0.0/1" -or $_.DestinationPrefix -eq "0.0.0.0/0") }
    if ($r) { return $true }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

function Get-Egress($tries) {
  for ($i = 1; $i -le $tries; $i++) {
    try {
      $v = (Invoke-WebRequest -Uri "https://api.ipify.org" -TimeoutSec 10 -UseBasicParsing).Content.Trim()
      if ($v -ne "") { return $v }
    } catch { }
    Start-Sleep -Seconds 3
  }
  return ""
}

function Stop-All {
  & sc.exe stop $svc2 | Out-Null
  Wait-Stopped $svc2 30 | Out-Null
  & sc.exe stop $svc1 | Out-Null
  Wait-Stopped $svc1 30 | Out-Null
  $gone2 = Wait-AdapterGone $Pair $GoneTimeout
  $gone1 = Wait-AdapterGone $hop1 $GoneTimeout
  if (-not $gone2) { ("  note: adapter " + $Pair + " was still present after " + $GoneTimeout + "s") | Add-Content -Path $log -Encoding ASCII }
  if (-not $gone1) { ("  note: adapter " + $hop1 + " was still present after " + $GoneTimeout + "s") | Add-Content -Path $log -Encoding ASCII }
  Start-Sleep -Seconds 2
}

function Dump-AppLog($cycle) {
  if (-not (Test-Path -LiteralPath $Exe)) { return }
  ("---- client log after failed cycle " + $cycle + " ----") | Add-Content -Path $applog -Encoding ASCII
  $tmp = Join-Path $env:TEMP "awgchain-dumplog.txt"
  & $Exe /dumplog /tail > $tmp 2>$null
  if (Test-Path $tmp) {
    Get-Content -LiteralPath $tmp -Tail 120 | Add-Content -Path $applog -Encoding UTF8
    Remove-Item -LiteralPath $tmp -Force
  }
}

# ---- what the address outside looks like WITHOUT the chain -----------------
# Anything that ever shows this address again is a leak, not a success. If the
# kill switch is armed there is no answer at all, which is just as good.
Stop-All
$leakAddr = Get-Egress 1
if ($leakAddr -ne "") {
  ("leak address (chain down): " + $leakAddr) | Add-Content -Path $log -Encoding ASCII
  Write-Host ("With the chain down this machine looks like {0}. Any cycle showing it counts as a leak." -f $leakAddr)
} else {
  "leak address (chain down): none, nothing got out" | Add-Content -Path $log -Encoding ASCII
  Write-Host "With the chain down nothing got out at all, which is what the kill switch is for."
}
if ($Expect -ne "") {
  ("expected egress: " + $Expect + " (given on the command line)") | Add-Content -Path $log -Encoding ASCII
  Write-Host ("Expected exit address: {0}" -f $Expect)
}

$ok = 0
$fail = 0
$leaks = 0
$upTimes = @()
Write-Host ("Running {0} cycles in mode {1}, this takes a while." -f $Cycles, $Mode)

for ($c = 1; $c -le $Cycles; $c++) {
  $note = ""
  Stop-All

  $t0 = Get-Date
  if ($Mode -eq "visible") {
    & sc.exe start $svc2 | Out-Null
  } else {
    & sc.exe start $svc1 | Out-Null
    if (-not (Wait-Adapter $hop1 $UpTimeout)) { $note = "hop1 did not come up" }
    & sc.exe start $svc2 | Out-Null
  }

  $up2 = Wait-Adapter $Pair $UpTimeout
  if (-not $up2 -and $note -eq "") { $note = "hop2 did not come up" }
  if (-not (Wait-Route $Pair 20) -and $note -eq "") { $note = "no chain default route" }
  $upSeconds = [int]((Get-Date) - $t0).TotalSeconds

  Start-Sleep -Seconds $Settle

  $egress = Get-Egress $EgressTries

  # The first cycle that comes up with both hops alive and a fresh address
  # sets the expectation for the whole run.
  if ($Expect -eq "" -and $egress -ne "" -and $egress -ne $leakAddr -and $note -eq "") {
    $Expect = $egress
    ("expected egress: " + $Expect + " (learned from cycle " + $c + ")") | Add-Content -Path $log -Encoding ASCII
    Write-Host ("Exit address of the chain: {0}. Every later cycle has to match it." -f $Expect)
  }

  $res = "FAIL"
  if ($egress -eq "") {
    if ($note -eq "") { $note = "no egress answer" }
  } elseif ($leakAddr -ne "" -and $egress -eq $leakAddr) {
    $res = "LEAK"
    if ($note -eq "") { $note = "traffic went straight out, not through the chain" }
  } elseif ($Expect -ne "" -and $egress -ne $Expect) {
    $res = "LEAK"
    if ($note -eq "") { $note = "egress is not the chain exit " + $Expect }
  } elseif ($note -ne "") {
    # the address is right, but something in the chain was not healthy
    $res = "FAIL"
  } else {
    $res = "OK"
  }

  $dnsMs = -1
  $d0 = Get-Date
  $r = Resolve-DnsName -Name "example.com" -Type A -ErrorAction SilentlyContinue
  if ($r) { $dnsMs = [int]((Get-Date) - $d0).TotalMilliseconds }

  $s1 = Svc-State $svc1
  $s2 = Svc-State $svc2

  if ($res -eq "OK") { $ok++; $upTimes += $upSeconds }
  elseif ($res -eq "LEAK") { $leaks++ }
  else { $fail++ }

  Write-Host ("cycle {0}/{1}  {2}  up={3}s  egress={4}  dns={5}ms  {6}" -f $c, $Cycles, $res, $upSeconds, $egress, $dnsMs, $note)
  ("{0},{1},{2},{3},{4},{5},{6},{7}" -f $c, $res, $upSeconds, $s1, $s2, $egress, $dnsMs, $note) | Add-Content -Path $csv -Encoding ASCII
  ((Get-Date -Format "HH:mm:ss") + " " + $c + "," + $res + "," + $upSeconds + "," + $s1 + "," + $s2 + "," + $egress + "," + $dnsMs + "," + $note) | Add-Content -Path $log -Encoding ASCII

  if ($res -ne "OK") {
    "--- diagnostics after a bad cycle ---" | Add-Content -Path $log -Encoding ASCII
    (Get-NetAdapter -IncludeHidden | Where-Object { $_.Name -eq $Pair -or $_.Name -eq $hop1 } | Format-Table ifIndex, Name, Status | Out-String) | Add-Content -Path $log -Encoding ASCII
    (Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Format-Table ifIndex, Name, Status | Out-String) | Add-Content -Path $log -Encoding ASCII
    (Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -like "0.0.0.0/*" -or $_.DestinationPrefix -eq "128.0.0.0/1" } | Format-Table ifIndex, InterfaceAlias, DestinationPrefix, NextHop, RouteMetric | Out-String) | Add-Content -Path $log -Encoding ASCII
    (Get-DnsClientServerAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, ServerAddresses | Out-String) | Add-Content -Path $log -Encoding ASCII
    Dump-AppLog $c
  }
}

$avg = 0
if ($upTimes.Count -gt 0) {
  $sum = 0
  foreach ($t in $upTimes) { $sum = $sum + $t }
  $avg = [int]($sum / $upTimes.Count)
}

Write-Host ""
Write-Host ("cycles: {0}  OK: {1}  FAIL: {2}  LEAK: {3}  average time to come up: {4}s" -f $Cycles, $ok, $fail, $leaks, $avg)
Write-Host ("csv: {0}" -f $csv)
("==== stress end OK=" + $ok + " FAIL=" + $fail + " LEAK=" + $leaks + " avg_up=" + $avg + " expect=" + $Expect) | Add-Content -Path $log -Encoding ASCII
if ($leaks -gt 0) { Write-Host "RESULT=LEAK" }
elseif ($fail -gt 0) { Write-Host "RESULT=FAIL" }
else { Write-Host "RESULT=OK" }
