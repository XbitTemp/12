# AwgChain patch 11 - the kill switch follows the chain when it is rebuilt
#
# What went wrong in the patch 10 test:
#   sc.exe stop AwgChainTunnel$hop1-warp
#   -> the watch repaired the chain and hop 1 came back
#   -> but the new wintun adapters carry new LUIDs
#   -> the running guard still permitted the hop 2 endpoint through the OLD
#      hop 1 LUID, so hop 2 could never handshake again
#
# Two files are replaced:
#   chainguard\main.go   the guard watches both LUIDs and rebuilds its filters
#   manager\chainguard.go the watch never gives up and never quietly unlocks
#
# No hooks are touched, so patch 10 must already be in place. Backups are
# kept once as <name>.orig-p11. Undo with -Revert. Re-running is safe.

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Here = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

$Here = ('' + $Here).Trim().Trim('"').Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Client = ('' + $Client).Trim().Trim('"').Trim().TrimEnd('\')

$fails = 0

function Say([string]$m) { Write-Host $m }
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Backup-Once([string]$path) {
  $b = $path + '.orig-p11'
  if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p11'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Write-Host ('[OK] ' + $label + ' was restored from the backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

Say '=================================================='
Say 'AwgChain patch 11 - the kill switch follows a rebuilt chain'
Say ('date   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('client : ' + $Client)
Say '=================================================='

$guardMain   = Join-Path $Client 'chainguard\main.go'
$managerFile = Join-Path $Client 'manager\chainguard.go'

if ($Revert) {
  Say '--- revert ---'
  Restore-Backup $guardMain 'chainguard\main.go'
  Restore-Backup $managerFile 'manager\chainguard.go'
  Say '=================================================='
  Say 'RESULT=REVERTED'
  Say 'Rebuild and reinstall to put the old behaviour back.'
  exit 0
}

# ------------------------------------------------------ 0. patch 10 present ---
Say '--- 0. patch 10 must be in place ---'
$ipcGo = Join-Path $Client 'manager\ipc_server.go'
if (-not (Test-Path -LiteralPath $ipcGo)) {
  Bad ('source file not found: ' + $ipcGo)
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}
$ipc = Get-Content -LiteralPath $ipcGo -Raw
if ($ipc -match 'chainInstallAndArm') {
  Ok 'patch 10 hooks are in ipc_server.go'
} else {
  Bad 'ipc_server.go has no patch 10 hook - run awgchain.bat patch10 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}
if (-not (Test-Path -LiteralPath $guardMain)) {
  Bad ('the guard source is missing: ' + $guardMain)
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

# ------------------------------------------------------ 1. the guard itself ---
Say '--- 1. chainguard\main.go ---'
$src = Join-Path $Here 'guard-main.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('guard-main.go was not found next to this script: ' + $src)
} else {
  Backup-Once $guardMain
  Copy-Item -LiteralPath $src -Destination $guardMain -Force
  Ok 'the guard now rebuilds its filters when the chain is rebuilt'
}

# ---------------------------------------------------- 2. the manager watch ---
Say '--- 2. manager\chainguard.go ---'
$src2 = Join-Path $Here 'chainguard.go'
if (-not (Test-Path -LiteralPath $src2)) {
  Bad ('chainguard.go was not found next to this script: ' + $src2)
} else {
  Backup-Once $managerFile
  Copy-Item -LiteralPath $src2 -Destination $managerFile -Force
  Ok 'the watch keeps trying and keeps the kill switch armed'
}

# ------------------------------------------------------------------ verdict ---
Say '=================================================='
if ($fails -eq 0) {
  Say 'RESULT=OK'
  Say 'Now rebuild both binaries and install them.'
  exit 0
}
Say ('RESULT=FAIL failed steps: ' + $fails)
exit 1
