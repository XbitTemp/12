# AwgChain patch 8 - the chain, in order, from inside the manager
#
# Two one-line hooks in manager\ipc_server.go plus one new file:
#
#   1. manager\chainorder.go   new file: parent/child of a hop, wait, order
#   2. Start()                 raise every hop underneath first
#   3. Stop()                  drop every hop on top first
#   4. chainui.go              the interface no longer asks for permission
#
# After this the graphical interface is enough: one toggle on hop 2 raises
# hop 1, waits for its handshake, then raises hop 2. One toggle off drops
# hop 2 first and hop 1 after it.
#
# Every touched file is backed up once as <name>.orig-p8. Undo with -Revert.
# Re-running is safe.

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Here = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

# A trailing backslash inside a quoted cmd argument escapes the closing quote.
$Here = ('' + $Here).Trim().Trim('"').Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Client = ('' + $Client).Trim().Trim('"').Trim().TrimEnd('\')

$fails = 0

function Say([string]$m) { Write-Host $m }
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Write-Text([string]$path, [string]$text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Backup-Once([string]$path) {
  $b = $path + '.orig-p8'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p8'
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
Say 'AwgChain patch 8 - chain ordering inside the manager'
Say ('date   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('client : ' + $Client)
Say '=================================================='

$ipcGo   = Join-Path $Client 'manager\ipc_server.go'
$orderGo = Join-Path $Client 'manager\chainorder.go'
$chainMgr = Join-Path $Client 'manager\chainmanager.go'
$uiGo    = Join-Path $Client 'chainui.go'

if (-not (Test-Path -LiteralPath $ipcGo)) {
  Bad ('source file not found: ' + $ipcGo)
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

# ---------------------------------------------------------------- revert ---
if ($Revert) {
  Say '--- revert ---'
  Restore-Backup $ipcGo 'manager\ipc_server.go'
  Restore-Backup $uiGo  'chainui.go'
  if (Test-Path -LiteralPath $orderGo) {
    Remove-Item -LiteralPath $orderGo -Force
    Ok 'manager\chainorder.go was removed'
  }
  Say '=================================================='
  Say 'RESULT=REVERTED'
  Say 'Rebuild and reinstall to put the old behaviour back.'
  exit 0
}

# ------------------------------------------------------ 0. patch 6 present ---
Say '--- 0. patch 6 must be in place ---'
if (-not (Test-Path -LiteralPath $chainMgr)) {
  Bad 'manager\chainmanager.go is missing - apply patch 6 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}
$ipc = Get-Content -LiteralPath $ipcGo -Raw
if ($ipc -match 'chainSiblings') {
  Ok 'patch 6 hooks are in ipc_server.go'
} else {
  Bad 'ipc_server.go has no patch 6 hook - run awgchain.bat patch6 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

# -------------------------------------------------------- 1. chainorder.go ---
Say '--- 1. manager\chainorder.go ---'
$src = Join-Path $Here 'chainorder.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('chainorder.go was not found next to this script: ' + $src)
} else {
  Copy-Item -LiteralPath $src -Destination $orderGo -Force
  Ok 'chainorder.go was copied into manager\'
}

# ------------------------------------------------ 2. Start raises parents ---
Say '--- 2. ipc_server.go: Start raises the hops underneath ---'
if ($ipc -match 'chainStartParents\(tunnelName, 0\)') {
  Ok 'Start already raises the hops underneath'
} else {
  $ins = @'
if err := s.chainStartParents(tunnelName, 0); err != nil {
	// AwgChain: a hop is useless without the hop it rides on, so bring the
	// lower ones up first and wait for each handshake.
	return err
}

'@
  $new = Insert-Before $ipc '(?m)^([ \t]*)// Figure out which tunnels have intersecting addresses/routes and stop those\.' $ins
  if ($new -eq $null) {
    Bad 'the anchor comment was not found in Start()'
  } else {
    Backup-Once $ipcGo
    Write-Text $ipcGo $new
    $ipc = $new
    Ok 'starting a hop now raises the whole chain underneath it'
  }
}

# --------------------------------------------- 3. Stop drops the hops above ---
Say '--- 3. ipc_server.go: Stop drops the hops on top first ---'
if ($ipc -match 'chainStopChildren\(tunnelName, 0\)') {
  Ok 'Stop already drops the hops on top first'
} else {
  $ins = @'
// AwgChain: whatever rides on this tunnel loses its way out the moment this
// one goes, so tear the upper hops down first.
s.chainStopChildren(tunnelName, 0)
'@
  $new = Insert-Before $ipc '(?m)^([ \t]*)err := UninstallTunnel\(tunnelName\)[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'the UninstallTunnel anchor was not found in Stop()'
  } else {
    Backup-Once $ipcGo
    Write-Text $ipcGo $new
    $ipc = $new
    Ok 'stopping a hop now drops the hops above it first'
  }
}

# ------------------------------------------------------------ 4. chainui.go ---
Say '--- 4. chainui.go: the interface opens without asking ---'
$uiSrc = Join-Path $Here 'chainui.go'
if (-not (Test-Path -LiteralPath $uiSrc)) {
  Bad ('chainui.go was not found next to this script: ' + $uiSrc)
} elseif (-not (Test-Path -LiteralPath $uiGo)) {
  Copy-Item -LiteralPath $uiSrc -Destination $uiGo -Force
  Ok 'chainui.go was copied into the client root'
} else {
  Backup-Once $uiGo
  Copy-Item -LiteralPath $uiSrc -Destination $uiGo -Force
  Ok 'chainui.go was replaced with the patch 8 version'
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
