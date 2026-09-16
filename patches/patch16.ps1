# AwgChain patch 16 - turning the chain off stops both hops
#
#   1. manager\chainorder.go   new version: the hidden hop comes down too
#   2. manager\ipc_server.go   Stop() drops the hidden hop underneath
#
# Patch 8 has to be applied first. Files are backed up once as
# <name>.orig-p16. Undo with -Revert. Re-running is safe.

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Core = 'C:\dev\vpnchain\amneziawg-windows',
  [string]$Here = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

$Here = ('' + $Here).Trim().Trim('"').Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Client = ('' + $Client).Trim().Trim('"').Trim().TrimEnd('\')
$Core = ('' + $Core).Trim().Trim('"').Trim().TrimEnd('\')

$fails = 0

function Say([string]$m) { Write-Host $m }
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Write-Text([string]$path, [string]$text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Backup-Once([string]$path) {
  $b = $path + '.orig-p16'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p16'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Write-Host ('[OK] ' + $label + ' was restored from the backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

function Insert-Before([string]$text, [string]$pattern, [string]$insert) {
  $rx = New-Object System.Text.RegularExpressions.Regex($pattern)
  $m = $rx.Match($text)
  if (-not $m.Success) { return $null }
  $nl = "`n"
  if ($text.Contains("`r`n")) { $nl = "`r`n" }
  $indent = $m.Groups[1].Value
  $body = ''
  foreach ($line in ($insert -split "`n")) {
    $l = $line.TrimEnd("`r")
    if ($l -eq '') { $body = $body + $nl }
    else { $body = $body + $indent + $l + $nl }
  }
  return $text.Substring(0, $m.Index) + $body + $text.Substring($m.Index)
}

function Replace-Once([string]$text, [string]$old, [string]$new) {
  $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
  if ($count -ne 1) { return $null }
  return $text.Replace($old, $new)
}
Say ''
Say '=== AwgChain patch 16: turning the chain off stops both hops ==='
Say ('client: ' + $Client)
Say ('here:   ' + $Here)
Say ''

function Insert-After([string]$text, [string]$pattern, [string]$insert) {
  $rx = New-Object System.Text.RegularExpressions.Regex($pattern)
  $m = $rx.Match($text)
  if (-not $m.Success) { return $null }
  $nl = "`n"
  if ($text.Contains("`r`n")) { $nl = "`r`n" }
  $indent = $m.Groups[1].Value
  $body = ''
  foreach ($line in ($insert -split "`n")) {
    $l = $line.TrimEnd("`r")
    if ($l -eq '') { $body = $body + $nl }
    else { $body = $body + $nl + $indent + $l }
  }
  $end = $m.Index + $m.Length
  return $text.Substring(0, $end) + $body + $text.Substring($end)
}

$orderSrc = Join-Path $Here 'chainorder.go'
$orderDst = Join-Path $Client 'manager\chainorder.go'
$ipcGo = Join-Path $Client 'manager\ipc_server.go'

if (-not (Test-Path -LiteralPath $ipcGo)) {
  Bad ('the source file was not found: ' + $ipcGo)
  Say 'RESULT=FAIL'
  exit 1
}

if ($Revert) {
  Say '--- revert ---'
  Restore-Backup $ipcGo 'manager\ipc_server.go'
  Restore-Backup $orderDst 'manager\chainorder.go'
  Say ''
  Say 'RESULT=REVERTED'
  Say 'Rebuild the client with: awgchain.bat build'
  exit 0
}

$ipc = Get-Content -LiteralPath $ipcGo -Raw
if (-not $ipc.Contains('chainStopChildren(tunnelName, 0)')) {
  Bad 'ipc_server.go carries no patch 8 hook, so run awgchain.bat patch8 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

Say '--- 1. manager\chainorder.go: the hidden hop comes down too ---'
if (-not (Test-Path -LiteralPath $orderSrc)) {
  Bad ('chainorder.go was not found next to this script: ' + $orderSrc)
} else {
  if (Test-Path -LiteralPath $orderDst) { Backup-Once $orderDst }
  Copy-Item -LiteralPath $orderSrc -Destination $orderDst -Force
  Ok 'manager\chainorder.go is in place'
}

Say '--- 2. ipc_server.go: Stop takes the hop underneath with it ---'
if ($ipc.Contains('chainStopHiddenParents(tunnelName, 0)')) {
  Ok 'Stop already drops the hidden hop underneath'
} else {
  $ins = @'
// AwgChain patch 16: a hidden hop is of no use once the tunnel that rode on
// it is gone, so it stands down as well.
s.chainStopHiddenParents(tunnelName, 0)
'@
  $new = Insert-After $ipc '(?m)^([ \t]*)err := UninstallTunnel\(tunnelName\)[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'the UninstallTunnel anchor from patch 8 was not found in Stop()'
  } else {
    Backup-Once $ipcGo
    Write-Text $ipcGo $new
    $ipc = $new
    Ok 'stopping a chain tunnel now stops the hidden WARP hop as well'
  }
}

Say ''
if ($fails -eq 0) {
  Say 'RESULT=OK'
  exit 0
}
Say ('RESULT=FAIL failed steps: ' + $fails)
exit 1
