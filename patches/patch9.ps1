# AwgChain patch 9 - the pin route lives inside the tunnel service
#
# Why: patch 8 let the interface raise the chain, but the host route that
# awgchain.bat used to add by hand went missing, so the handshake of hop 2
# looped back into hop 2 itself. This patch teaches the tunnel service to lay
# that route itself, on the adapter named by PinEndpointVia.
#
#   1. tunnel\pinroute.go   new file: endpoints, next hop, add/remove
#   2. service.go           lay the route while starting, before the firewall
#   3. service.go           take it away again while stopping
#
# Files are backed up once as <name>.orig-p9. Undo with -Revert. Re-running
# is safe.

param(
  [string]$Core = 'C:\dev\vpnchain\amneziawg-windows',
  [string]$Here = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

# A trailing backslash inside a quoted cmd argument escapes the closing quote.
$Here = ('' + $Here).Trim().Trim('"').Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
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
  $b = $path + '.orig-p9'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p9'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Write-Host ('[OK] ' + $label + ' was restored from the backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

# Insert $insert immediately before the first line matching $pattern, using the
# indentation of that line. Returns the new text, or $null if no anchor.
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

Say '=================================================='
Say 'AwgChain patch 9 - the pin route inside the tunnel'
Say ('date : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('core : ' + $Core)
Say '=================================================='

$svcGo = Join-Path $Core 'tunnel\service.go'
$pinGo = Join-Path $Core 'tunnel\pinroute.go'
$p1Go  = Join-Path $Core 'tunnel\pinendpoint.go'

if (-not (Test-Path -LiteralPath $svcGo)) {
  Bad ('source file not found: ' + $svcGo)
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

# ---------------------------------------------------------------- revert ---
if ($Revert) {
  Say '--- revert ---'
  Restore-Backup $svcGo 'tunnel\service.go'
  if (Test-Path -LiteralPath $pinGo) {
    Remove-Item -LiteralPath $pinGo -Force
    Ok 'tunnel\pinroute.go was removed'
  }
  Say '=================================================='
  Say 'RESULT=REVERTED'
  Say 'Rebuild and reinstall to put the old behaviour back.'
  exit 0
}

# ------------------------------------------------------ 0. patch 1 present ---
Say '--- 0. patch 1 must be in place ---'
if (Test-Path -LiteralPath $p1Go) {
  Ok 'tunnel\pinendpoint.go from patch 1 is here'
} else {
  Bad 'tunnel\pinendpoint.go is missing - apply patch 1 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

# --------------------------------------------------------- 1. pinroute.go ---
Say '--- 1. tunnel\pinroute.go ---'
$src = Join-Path $Here 'pinroute.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('pinroute.go was not found next to this script: ' + $src)
} else {
  Copy-Item -LiteralPath $src -Destination $pinGo -Force
  Ok 'pinroute.go was copied into tunnel\'
}

$svc = Get-Content -LiteralPath $svcGo -Raw

# ------------------------------------------------- 2. lay the route on up ---
Say '--- 2. service.go: lay the pin route while starting ---'
if ($svc -match 'chainPinRoutes\(config, true\)') {
  Ok 'the tunnel already lays its pin route'
} else {
  $ins = @'
// AwgChain: IP_UNICAST_IF alone does not survive the routes that the hop
// above installs, so give the endpoint of this hop a host route on the
// adapter it is pinned to. No PinEndpointVia, nothing happens.
chainPinRoutes(config, true)

'@
  $new = Insert-Before $svc '(?m)^([ \t]*)err = enableFirewall\(config, nativeTun\)' $ins
  if ($new -eq $null) {
    Bad 'the enableFirewall anchor was not found in service.go'
  } else {
    Backup-Once $svcGo
    Write-Text $svcGo $new
    $svc = $new
    Ok 'the endpoint of a pinned hop now gets its own host route'
  }
}

# ----------------------------------------------- 3. take it away on down ---
Say '--- 3. service.go: take the pin route away while stopping ---'
if ($svc -match 'chainPinRoutes\(config, false\)') {
  Ok 'the tunnel already removes its pin route'
} else {
  $ins = @'
if config != nil {
	// AwgChain: the host route goes down with the tunnel that needed it.
	chainPinRoutes(config, false)
}
'@
  $new = Insert-Before $svc '(?m)^([ \t]*)if watcher != nil \{' $ins
  if ($new -eq $null) {
    Bad 'the watcher anchor was not found in service.go'
  } else {
    Backup-Once $svcGo
    Write-Text $svcGo $new
    $svc = $new
    Ok 'the host route is removed again when the hop stops'
  }
}

# ------------------------------------------------------------------ verdict ---
Say '=================================================='
if ($fails -eq 0) {
  Say 'RESULT=OK'
  Say 'Now rebuild, install, and drive the chain from the interface.'
  exit 0
}
Say ('RESULT=FAIL failed steps: ' + $fails)
exit 1
