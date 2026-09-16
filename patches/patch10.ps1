# AwgChain patch 10 - the chain arms its own kill switch and watches itself
#
# One new file plus two hooks in manager\ipc_server.go:
#
#   1. manager\chainguard.go   arm, disarm, watch, repair
#   2. Start()                 the top hop arms the kill switch and the watch
#   3. Stop()                  both stand down again
#
# After this nothing has to be typed to get a protected chain: one toggle in
# the interface raises both hops, arms the kill switch and starts the watch.
#
# Every touched file is backed up once as <name>.orig-p10. Undo with -Revert.
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
  $b = $path + '.orig-p10'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p10'
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

# Replace the first match of $pattern with $replacement. Returns $null if no
# match, so the caller can report a missing anchor.
function Replace-Once([string]$text, [string]$pattern, [string]$replacement) {
  $rx = New-Object System.Text.RegularExpressions.Regex($pattern)
  if (-not $rx.IsMatch($text)) { return $null }
  return $rx.Replace($text, $replacement, 1)
}

Say '=================================================='
Say 'AwgChain patch 10 - kill switch and watch in the manager'
Say ('date   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('client : ' + $Client)
Say '=================================================='

$ipcGo    = Join-Path $Client 'manager\ipc_server.go'
$guardGo  = Join-Path $Client 'manager\chainguard.go'
$orderGo  = Join-Path $Client 'manager\chainorder.go'

if (-not (Test-Path -LiteralPath $ipcGo)) {
  Bad ('source file not found: ' + $ipcGo)
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

# ---------------------------------------------------------------- revert ---
if ($Revert) {
  Say '--- revert ---'
  Restore-Backup $ipcGo 'manager\ipc_server.go'
  if (Test-Path -LiteralPath $guardGo) {
    Remove-Item -LiteralPath $guardGo -Force
    Ok 'manager\chainguard.go was removed'
  }
  Say '=================================================='
  Say 'RESULT=REVERTED'
  Say 'Rebuild and reinstall to put the old behaviour back.'
  exit 0
}

# ------------------------------------------------------ 0. patch 8 present ---
Say '--- 0. patch 8 must be in place ---'
if (-not (Test-Path -LiteralPath $orderGo)) {
  Bad 'manager\chainorder.go is missing - apply patch 8 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}
$ipc = Get-Content -LiteralPath $ipcGo -Raw
if ($ipc -match 'chainStartParents') {
  Ok 'patch 8 hooks are in ipc_server.go'
} else {
  Bad 'ipc_server.go has no patch 8 hook - run awgchain.bat patch8 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

# -------------------------------------------------------- 1. chainguard.go ---
Say '--- 1. manager\chainguard.go ---'
$src = Join-Path $Here 'chainguard.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('chainguard.go was not found next to this script: ' + $src)
} else {
  Copy-Item -LiteralPath $src -Destination $guardGo -Force
  Ok 'chainguard.go was copied into manager\'
}

# ------------------------------------------------- 2. Start arms the chain ---
Say '--- 2. ipc_server.go: the top hop arms the kill switch ---'
if ($ipc -match 'chainInstallAndArm') {
  Ok 'Start already arms the chain'
} else {
  $new = Replace-Once $ipc '(?m)^([ \t]*)return InstallTunnel\(path\)' '$1return s.chainInstallAndArm(tunnelName, path)'
  if ($new -eq $null) {
    Bad 'the InstallTunnel anchor was not found in Start()'
  } else {
    Backup-Once $ipcGo
    Write-Text $ipcGo $new
    $ipc = $new
    Ok 'starting the top hop now arms the kill switch and the watch'
  }
}

# ------------------------------------------- 3. Stop lets everything go ---
Say '--- 3. ipc_server.go: stopping a hop stands the kill switch down ---'
if ($ipc -match 'chainBeforeStop\(tunnelName\)') {
  Ok 'Stop already stands the kill switch down'
} else {
  $ins = @'
// AwgChain: a deliberate stop takes the watch and the kill switch with it.
// A repair goes through UninstallTunnel directly and so leaves them armed.
s.chainBeforeStop(tunnelName)
'@
  $new = Insert-Before $ipc '(?m)^([ \t]*)s\.chainStopChildren\(tunnelName, 0\)' $ins
  if ($new -eq $null) {
    Bad 'the chainStopChildren anchor from patch 8 was not found in Stop()'
  } else {
    Backup-Once $ipcGo
    Write-Text $ipcGo $new
    $ipc = $new
    Ok 'stopping a hop now disarms the kill switch and stops the watch'
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
