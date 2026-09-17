# AwgChain patch34 (pack 53)
# The re-arm after a repair no longer opens a two second window:
# the old rule set is held until both fresh adapters exist, then the sets are
# swapped back to back. Retry step 2s -> 200ms.
#
# Touches one file: manager\chainrelock.go (whole file from the template).
# Backup: chainrelock.go.orig-p53 ;  rollback:  -Revert

param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($m) { Write-Host $m }
function Ok($m)  { Write-Host "[OK] $m" }
function Bad($m) { Write-Host "[FAIL] $m" }

$mgr    = 'C:\dev\vpnchain\amneziawg-windows-client\manager'
$target = Join-Path $mgr 'chainrelock.go'
$backup = $target + '.orig-p53'
$tpl    = Join-Path $PSScriptRoot 'p53-chainrelock.go.txt'
$enc    = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $mgr)) { Bad "not found: $mgr"; Write-Host 'RESULT=FAIL reason=nodir'; exit 1 }

if ($Revert) {
	if (-not (Test-Path $backup)) { Bad "no backup: $backup"; Write-Host 'RESULT=FAIL reason=nobackup'; exit 1 }
	$old = [System.IO.File]::ReadAllText($backup)
	[System.IO.File]::WriteAllText($target, $old, $enc)
	Ok "restored : $target"
	Write-Host 'RESULT=REVERTED'
	exit 0
}

if (-not (Test-Path $target)) { Bad "not found: $target (apply pack 52 first)"; Write-Host 'RESULT=FAIL reason=nofile'; exit 1 }
if (-not (Test-Path $tpl))    { Bad "not found: $tpl"; Write-Host 'RESULT=FAIL reason=notemplate'; exit 1 }

$current = [System.IO.File]::ReadAllText($target)

if ($current.Contains('chainRelockAdaptersReady')) {
	Ok 'chainrelock.go already carries pack 53, nothing to do'
	Write-Host 'RESULT=OK'
	exit 0
}

if (-not (Test-Path $backup)) {
	[System.IO.File]::WriteAllText($backup, $current, $enc)
	Say "backup   : $backup"
}

$body = [System.IO.File]::ReadAllText($tpl)
$body = $body -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($target, $body, $enc)
Ok "wrote    : $target"

# The guard file must still call us, otherwise the new code is dead weight.
$guard = Join-Path $mgr 'chainguard.go'
if (Test-Path $guard) {
	$g = [System.IO.File]::ReadAllText($guard)
	if ($g.Contains('chainRearmLockAfterRepair')) {
		Ok 'chainguard.go still calls the re-arm after a repair'
	} else {
		Bad 'chainguard.go does NOT call chainRearmLockAfterRepair - apply patch33 (pack 52) first'
		Write-Host 'RESULT=FAIL reason=nohook'
		exit 1
	}
}

Write-Host 'RESULT=OK'
exit 0
