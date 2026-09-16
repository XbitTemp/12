# AwgChain patch 20 - the chain gets help when it needs it.
#
# Two real faults were found in the log of 2026-09-15:
#
#   1. manager\chainguard.go  the repair counter never went back to zero, so
#                             after twenty repairs over the whole life of the
#                             manager the watch dropped to one try every five
#                             minutes - even though every single repair was
#                             succeeding in seven seconds. This is what made
#                             stress 10 visible give 4 OK and 6 FAIL in the
#                             rhythm OK-FAIL-FAIL.
#   2. manager\chainorder.go   raising a hop was given exactly one attempt. A
#                             hop service that is still finishing its stop
#                             refuses to start ("please allow the tunnel to
#                             finish activating"), which threw away the whole
#                             attempt. Now the hop is waited for and retried.
#
# New file: manager\chainretry.go
# Backups:  chainguard.go.orig-p20, chainorder.go.orig-p20
# Undo with -Revert. Re-running is safe.

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
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Skip([string]$m) { Write-Host ('[SKIP] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Write-Go([string]$path, [string]$text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  $text = $text -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Backup-Once([string]$path) {
  $b = $path + '.orig-p20'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  original kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p20'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Ok ($label + ' restored from backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

$mgrDir = Join-Path $Client 'manager'
$guardGo = Join-Path $mgrDir 'chainguard.go'
$orderGo = Join-Path $mgrDir 'chainorder.go'
$retryGo = Join-Path $mgrDir 'chainretry.go'

Write-Host '=== AwgChain patch 20: repair counter and hop start retry ==='
Write-Host ('client  : ' + $Client)

if (-not (Test-Path -LiteralPath $mgrDir)) { Bad ('no manager folder: ' + $mgrDir); Write-Host 'RESULT=FAIL'; exit 1 }
if (-not (Test-Path -LiteralPath $guardGo)) { Bad ('patch 10 is not applied, no ' + $guardGo); Write-Host 'RESULT=FAIL'; exit 1 }
if (-not (Test-Path -LiteralPath $orderGo)) { Bad ('patch 8 is not applied, no ' + $orderGo); Write-Host 'RESULT=FAIL'; exit 1 }

if ($Revert) {
  Restore-Backup $guardGo 'manager\chainguard.go'
  Restore-Backup $orderGo 'manager\chainorder.go'
  if (Test-Path -LiteralPath $retryGo) { Remove-Item -LiteralPath $retryGo -Force; Ok 'manager\chainretry.go removed' }
  if ($fails -gt 0) { Write-Host 'RESULT=FAIL'; exit 1 }
  Write-Host 'RESULT=OK'
  Write-Host 'Now rebuild and install:  awgchain.bat build   then   awgchain.bat install'
  exit 0
}

# ---------------------------------------------------------------------------
# 1. new file: manager\chainretry.go
# ---------------------------------------------------------------------------

$retrySrc = @'
//go:build windows

/* AwgChain - patch 20: a hop is given more than one chance to start.
 *
 * chainStartParents called ManagerService.Start once. When the service of the
 * hop underneath was still finishing its own shutdown, Windows refused the
 * start and the manager reported
 *
 *   Please allow the tunnel <name> to finish activating
 *
 * The whole repair attempt was then thrown away, even though waiting two
 * seconds would have been enough. The log of 2026-09-15 shows this happening
 * on try 1 and try 2 of every single repair, with try 3 always succeeding.
 *
 * Every start error is treated the same way here on purpose: the message from
 * the manager is localised, so matching on its text would break on a
 * non-English Windows.
 */

package manager

import (
	"log"
	"time"
)

const (
	chainHopStartTries    = 5
	chainHopStartRetryGap = 2 * time.Second
)

// chainStartHopWithRetry starts a hop, waiting for a service that is still
// busy instead of giving the whole attempt away.
func (s *ManagerService) chainStartHopWithRetry(name string) error {
	var err error
	for try := 1; try <= chainHopStartTries; try++ {
		err = s.Start(name)
		if err == nil {
			if try > 1 {
				log.Printf("[%s] Chain: the hop started on try %d", name, try)
			}
			return nil
		}
		if try == chainHopStartTries {
			break
		}
		log.Printf("[%s] Chain: the hop service is not ready yet (try %d of %d): %v", name, try, chainHopStartTries, err)
		s.chainWaitStopped(name)
		time.Sleep(chainHopStartRetryGap)
	}
	return err
}
'@

Write-Go $retryGo $retrySrc
Ok 'manager\chainretry.go written'

# ---------------------------------------------------------------------------
# 2. manager\chainguard.go - the repair counter counts failures in a row
# ---------------------------------------------------------------------------

$newWatch = @'
func (s *ManagerService) chainWatch(leaf string, stop chan struct{}) {
	// chainWatch v2 (patch 20): the counter below counts failures in a row.
	// It used to count every repair ever made by this manager, so twenty
	// repairs spread over days pushed the watch into its five minute mode for
	// good. A chain that went down after that waited minutes for help even
	// though each repair was finishing in seven seconds.
	log.Printf("[AwgChain] Watching the chain that ends at %s", leaf)
	failures := 0
	slow := false
	var lastRepair time.Time
	for {
		select {
		case <-stop:
			log.Printf("[AwgChain] No longer watching the chain")
			return
		case <-time.After(chainWatchInterval):
		}

		reason := s.chainTrouble(leaf)
		if reason == "" {
			// A healthy chain is also the moment to arm a kill switch that is
			// not up yet, for instance because the first try ran before the
			// interfaces existed. Arming twice is harmless.
			if failures > 0 {
				log.Printf("[AwgChain] The chain is healthy again, the repair counter goes back to zero")
			}
			failures = 0
			slow = false
			s.chainArmGuard(leaf)
			continue
		}
		grace := chainRepairGrace
		if slow {
			grace = chainSlowRepairGrace
		}
		if !lastRepair.IsZero() && time.Since(lastRepair) < grace {
			continue
		}
		failures++
		log.Printf("[AwgChain] The chain needs repair: %s (failure %d in a row)", reason, failures)
		s.chainRepair(leaf)
		lastRepair = time.Now()
		if failures >= chainMaxRepairs && !slow {
			// Never give up and never quietly let go of the kill switch: a
			// chain that cannot be fixed must not turn into plain traffic.
			slow = true
			log.Printf("[AwgChain] %d repairs in a row did not help (%s), so it is retried every %v from now on, with the kill switch still armed", failures, reason, chainSlowRepairGrace)
		}
	}
}
'@

$gtext = [System.IO.File]::ReadAllText($guardGo)
if ($gtext.Contains('chainWatch v2')) {
  Skip 'manager\chainguard.go already carries watch v2'
} else {
  $a = 'func (s *ManagerService) chainWatch(leaf string, stop chan struct{}) {'
  $b = 'func (s *ManagerService) chainStartWatch(leaf string) {'
  $i = $gtext.IndexOf($a)
  $j = $gtext.IndexOf($b)
  if ($i -lt 0) {
    Bad 'anchor not found: chainWatch function head'
  } elseif ($j -le $i) {
    Bad 'anchor not found: chainStartWatch function head after chainWatch'
  } else {
    Backup-Once $guardGo
    $head = $gtext.Substring(0, $i)
    $tail = $gtext.Substring($j)
    Write-Go $guardGo ($head + $newWatch.Trim() + "`n`n" + $tail)
    Ok 'manager\chainguard.go: the repair counter now counts failures in a row'
  }
}

# ---------------------------------------------------------------------------
# 3. manager\chainorder.go - raising a hop is retried
# ---------------------------------------------------------------------------

$otext = [System.IO.File]::ReadAllText($orderGo)
if ($otext.Contains('chainStartHopWithRetry')) {
  Skip 'manager\chainorder.go already retries the hop start'
} else {
  $a2 = "`terr = s.Start(parent)"
  if ($otext.Contains($a2)) {
    Backup-Once $orderGo
    $otext = $otext.Replace($a2, "`terr = s.chainStartHopWithRetry(parent)")
    Write-Go $orderGo $otext
    Ok 'manager\chainorder.go: the hop underneath is retried instead of failing at once'
  } else {
    Bad 'anchor not found: err = s.Start(parent) in chainStartParents'
  }
}

if ($fails -gt 0) {
  Write-Host ''
  Write-Host 'RESULT=FAIL'
  Write-Host 'Send C:\vpn\logs\patch20-log.txt to the chat.'
  exit 1
}

Write-Host ''
Write-Host 'RESULT=OK'
Write-Host 'Next:  awgchain.bat build   then   awgchain.bat install'
exit 0
