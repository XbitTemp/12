# AwgChain patch 6 - chain mode in the manager
#
# Three surgical edits in upstream files, all of them one-liners that call
# into chainmanager.go, plus the softened UI guard:
#
#   1. manager\chainmanager.go   new file: what a chain hop is
#   2. manager\ipc_server.go     Start() no longer stops a chain sibling
#   3. tunnel\addressconfig.go   a chain hop does not raise its own kill switch
#   4. manager\install.go        a running chain hop is adopted, not refused
#   5. chainui.go                the hard block becomes a question
#
# Files 2 and 4 live in the client repo, file 3 in the core fork.
# Every file is backed up once as <name>.orig-p6. Undo with -Revert.
# Re-running is safe: each step checks whether it is already applied.

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Core   = 'C:\dev\vpnchain\amneziawg-windows',
  [string]$Here   = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

# A trailing backslash inside a quoted cmd argument escapes the closing quote.
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
  $b = $path + '.orig-p6'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p6'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Write-Host ('[OK] ' + $label + ' was restored from the backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

# Insert $insert immediately before the first line matching $pattern.
# Returns the new text, or $null when the anchor was not found.
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
Say 'AwgChain patch 6 - chain mode in the manager'
Say ('date   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('client : ' + $Client)
Say ('core   : ' + $Core)
Say '=================================================='

$ipcGo   = Join-Path $Client 'manager\ipc_server.go'
$instGo  = Join-Path $Client 'manager\install.go'
$chainGo = Join-Path $Client 'manager\chainmanager.go'
$uiGo    = Join-Path $Client 'chainui.go'
$addrGo  = Join-Path $Core 'tunnel\addressconfig.go'
$confGo  = Join-Path $Core 'conf\config.go'

foreach ($p in @($ipcGo, $instGo, $addrGo, $confGo)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Bad ('source file not found: ' + $p)
    Say 'RESULT=FAIL nothing was changed'
    exit 1
  }
}

# ---------------------------------------------------------------- revert ---
if ($Revert) {
  Say '--- revert ---'
  Restore-Backup $ipcGo  'manager\ipc_server.go'
  Restore-Backup $instGo 'manager\install.go'
  Restore-Backup $addrGo 'tunnel\addressconfig.go'
  if (Test-Path -LiteralPath $chainGo) {
    Remove-Item -LiteralPath $chainGo -Force
    Ok 'manager\chainmanager.go was removed'
  }
  Restore-Backup $uiGo 'chainui.go'
  Say '=================================================='
  Say 'RESULT=REVERTED'
  Say 'Rebuild and reinstall to put the old behaviour back.'
  exit 0
}

# ------------------------------------------------- 0. the PinEndpointVia field ---
Say '--- 0. the chain field in conf ---'
$cf = Get-Content -LiteralPath $confGo -Raw
if ($cf -match 'PinEndpointVia') {
  foreach ($line in (Get-Content -LiteralPath $confGo)) {
    if ($line -match 'PinEndpointVia') { Say ('  found: ' + $line.Trim()) }
  }
  Ok 'patch 1 is in place, the manager can recognise a chain hop'
} else {
  Bad 'conf\config.go has no PinEndpointVia field - apply patch 1 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

# ------------------------------------------------------ 1. chainmanager.go ---
Say '--- 1. manager\chainmanager.go ---'
$src = Join-Path $Here 'chainmanager.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('chainmanager.go was not found next to this script: ' + $src)
} else {
  Copy-Item -LiteralPath $src -Destination $chainGo -Force
  Ok 'chainmanager.go was copied into manager\'
}

# ------------------------------------------------------- 2. ipc_server.go ---
Say '--- 2. manager\ipc_server.go: keep chain siblings alive ---'
$t = Get-Content -LiteralPath $ipcGo -Raw
if ($t -match 'chainSiblings') {
  Ok 'Start() already skips chain siblings'
} else {
  $ins = @'
if chainSiblings(c, c2) {
	// AwgChain: hops of one chain are meant to run together. The inner hop
	// pins its endpoint through the outer one, so the overlap is by design.
	log.Printf("[%s] Keeping chain sibling \u2018%s\u2019 running", c.Name, t)
	continue
}
'@
  $new = Insert-Before $t '(?m)^([ \t]*)tt = append\(tt, t\)[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'the tt = append(tt, t) anchor was not found in Start()'
  } else {
    Backup-Once $ipcGo
    Write-Text $ipcGo $new
    Ok 'Start() now leaves the other hop of the same chain running'
  }
}

# --------------------------------------------------- 3. addressconfig.go ---
Say '--- 3. tunnel\addressconfig.go: no per-hop kill switch ---'
$t = Get-Content -LiteralPath $addrGo -Raw
if ($t -match 'the chain rule set owns the kill switch') {
  Ok 'enableFirewall already steps aside for chain hops'
} else {
  $ins = @'
if conf.Interface.PinEndpointVia != "" {
	// AwgChain: this tunnel is a hop of a chain. The chain-wide rule set owns
	// the kill switch; a per-tunnel block-all here would land in a permanent
	// WFP session that the chain guard cannot remove.
	log.Println("Chain hop: leaving the kill switch to the chain rule set")
	return firewall.EnableFirewall(tun.LUID(), true, conf.Interface.DNS)
}
'@
  $new = Insert-Before $t '(?m)^([ \t]*)log\.Println\("Enabling firewall rules"\)[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'the Enabling firewall rules anchor was not found in enableFirewall()'
  } else {
    Backup-Once $addrGo
    Write-Text $addrGo $new
    Ok 'a chain hop now keeps its hands off the firewall'
  }
}

# ---------------------------------------------------------- 4. install.go ---
Say '--- 4. manager\install.go: adopt a running hop ---'
$t = Get-Content -LiteralPath $instGo -Raw
if ($t -match 'chainHopByName') {
  Ok 'InstallTunnel already adopts a running chain hop'
} else {
  $ins = @'
if chainHopByName(name) {
	// AwgChain: this hop is already up, most likely started by awgchain.bat or
	// by the chain watchdog. Adopt the existing service instead of refusing:
	// recreating it would drop its Nsi/TcpIp dependencies and bounce the chain.
	log.Printf("[%s] Adopting the running tunnel service", name)
	go trackTunnelService(name, service) // Pass off reference to handle.
	return nil
}
'@
  $pattern = '(?m)^([ \t]*)service\.Close\(\)[ \t]*\r?\n[ \t]*return errors\.New\("Tunnel already installed and running"\)'
  $new = Insert-Before $t $pattern $ins
  if ($new -eq $null) {
    Bad 'the "Tunnel already installed and running" anchor was not found'
  } else {
    Backup-Once $instGo
    Write-Text $instGo $new
    Ok 'a running chain hop is adopted, its service is left untouched'
  }
}

# ------------------------------------------------------------- 5. the UI ---
Say '--- 5. chainui.go: the block becomes a question ---'
$src = Join-Path $Here 'chainui.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('chainui.go was not found next to this script: ' + $src)
} else {
  if (Test-Path -LiteralPath $uiGo) { Backup-Once $uiGo }
  Copy-Item -LiteralPath $src -Destination $uiGo -Force
  Ok 'chainui.go was replaced with the patch 6 version'
}

Say '=================================================='
if ($fails -eq 0) {
  Say 'RESULT=OK'
  exit 0
}
Say ('RESULT=FAIL failed steps: ' + $fails)
exit 1
