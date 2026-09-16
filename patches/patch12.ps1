# AwgChain patch 12 - repair the chain in seconds instead of minutes
#
# What the patch 11 test showed, straight from the manager journal:
#
#   21:17:29  The chain needs repair: hop1-warp is not running (attempt 1)
#   21:17:31  Repair: could not raise the chain again:
#             Please allow the tunnel 'hop1-warp' to finish activating
#   21:19:11  The chain needs repair: hop1-warp is not running (attempt 2)
#   21:19:14  Repair: the chain is back up
#
# The repair itself is sound - the chain did come back, both hops ALIVE - but
# it raised the chain two seconds after tearing it down, while the hop was
# still shutting down. The manager refuses that, and the watch then sat out a
# whole 90 second grace period before trying again. Two minutes of silence.
#
# This patch replaces manager\chainguard.go with a version that:
#   - waits until every hop really is stopped before raising the chain
#   - retries the raise up to 6 times, 3 seconds apart, inside one repair
#   - looks at the chain every 5 seconds instead of every 20
#   - shortens the grace between repairs from 90 to 25 seconds
#   - logs how many seconds the repair took
#
# Only one file changes and no hooks are touched, so patches 10 and 11 must
# already be in place. Backup: manager\chainguard.go.orig-p12. Undo with
# -Revert. Re-running is safe.

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
  $b = $path + '.orig-p12'
  if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p12'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Write-Host ('[OK] ' + $label + ' was restored from the backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

Say '=================================================='
Say 'AwgChain patch 12 - a repair that takes seconds'
Say ('date   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('client : ' + $Client)
Say '=================================================='

$managerFile = Join-Path $Client 'manager\chainguard.go'

if ($Revert) {
  Say '--- revert ---'
  Restore-Backup $managerFile 'manager\chainguard.go'
  Say '=================================================='
  Say 'RESULT=REVERTED'
  Say 'Rebuild and reinstall to put the old behaviour back.'
  exit 0
}

Say '--- 0. patches 10 and 11 must be in place ---'
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
if (-not (Test-Path -LiteralPath $managerFile)) {
  Bad ('manager\chainguard.go is missing - run awgchain.bat patch10 first')
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

Say '--- 1. manager\chainguard.go ---'
$src = Join-Path $Here 'chainguard.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('chainguard.go was not found next to this script: ' + $src)
} else {
  Backup-Once $managerFile
  Copy-Item -LiteralPath $src -Destination $managerFile -Force
  Ok 'the repair now waits for a clean stop and retries straight away'
}

Say '=================================================='
if ($fails -eq 0) {
  Say 'RESULT=OK'
  Say 'Now rebuild the client and install it.'
  exit 0
}
Say ('RESULT=FAIL failed steps: ' + $fails)
exit 1
