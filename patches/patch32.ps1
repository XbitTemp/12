# AwgChain patch 32 (pack 51)
# The chain kill switch moves from awgchain-guard.exe into the manager service.
#   1. adds manager\chainlock.go
#   2. two one-line hooks in manager\chainguard.go
# Backups: <file>.orig-p51 ;  rollback:  -Revert

param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($m) { Write-Host $m }
function Ok($m)  { Write-Host "[OK] $m" }
function Bad($m) { Write-Host "[FAIL] $m" }

$mgr     = 'C:\dev\vpnchain\amneziawg-windows-client\manager'
$guard   = Join-Path $mgr 'chainguard.go'
$lock    = Join-Path $mgr 'chainlock.go'
$backup  = $guard + '.orig-p51'
$tpl     = Join-Path $PSScriptRoot 'p51-chainlock.go.txt'
$enc     = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $guard)) { Bad "not found: $guard"; Write-Host 'RESULT=FAIL reason=nofile'; exit 1 }

if ($Revert) {
	if (-not (Test-Path $backup)) { Bad "no backup: $backup"; Write-Host 'RESULT=FAIL reason=nobackup'; exit 1 }
	Copy-Item $backup $guard -Force
	if (Test-Path $lock) { Remove-Item $lock -Force }
	Ok "restored : $guard"
	Ok 'chainlock.go removed, the guard process is back'
	Write-Host 'RESULT=REVERTED'
	exit 0
}

if (-not (Test-Path $tpl)) { Bad "not found: $tpl"; Write-Host 'RESULT=FAIL reason=notemplate'; exit 1 }

# --- 1. the new file -------------------------------------------------------
$body = [System.IO.File]::ReadAllText($tpl)
$body = $body -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($lock, $body, $enc)
Ok "written  : $lock"

# --- 2. the two hooks ------------------------------------------------------
$text = [System.IO.File]::ReadAllText($guard)
$text = $text -replace "`r`n", "`n"

if ($text.Contains('chainArmLockInProc(leaf)')) {
	Ok 'chainguard.go already has the hooks, nothing to do'
	Write-Host 'RESULT=OK'
	exit 0
}

if (-not (Test-Path $backup)) {
	[System.IO.File]::WriteAllText($backup, $text, $enc)
	Say "backup   : $backup"
}

$lines = $text.Split("`n")
$anchor1 = -1
$anchor2 = -1
for ($i = 0; $i -lt $lines.Length; $i++) {
	if ($lines[$i].Contains('already := chainGuardProcess != nil')) { $anchor1 = $i }
	if ($lines[$i].TrimEnd() -eq 'func chainDisarmGuard() {')        { $anchor2 = $i }
}
if ($anchor1 -lt 0) { Bad 'anchor 1 not found (already := chainGuardProcess)'; Write-Host 'RESULT=FAIL reason=anchor1'; exit 1 }
if ($anchor2 -lt 0) { Bad 'anchor 2 not found (func chainDisarmGuard)';        Write-Host 'RESULT=FAIL reason=anchor2'; exit 1 }

# after anchor 1 the code reads:  chainGuardLock.Unlock() / if already { / return / }
$close1 = -1
for ($i = $anchor1; $i -lt [Math]::Min($anchor1 + 8, $lines.Length); $i++) {
	if ($lines[$i].TrimEnd() -eq ("`t" + 'if already {')) {
		$close1 = $i + 2
		break
	}
}
if ($close1 -lt 0 -or $lines[$close1].Trim() -ne '}') { Bad 'the if-already block does not look as expected'; Write-Host 'RESULT=FAIL reason=shape'; exit 1 }

$hook1 = @(
	'',
	("`t" + '// Pack 51: the lock now lives in this process. Only when that is not'),
	("`t" + '// possible do we fall back to starting awgchain-guard.exe.'),
	("`t" + 'if chainArmLockInProc(leaf) {'),
	("`t`t" + 'chainGuardNoteArm()'),
	("`t`t" + 'return'),
	("`t" + '}')
)
$hook2 = @(
	("`t" + '// Pack 51: an in-process lock is lifted here and now, with no grace timer.'),
	("`t" + 'chainDisarmLockInProc()')
)

$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Length; $i++) {
	$out.Add($lines[$i])
	if ($i -eq $close1) { foreach ($h in $hook1) { $out.Add($h) } }
	if ($i -eq $anchor2) { foreach ($h in $hook2) { $out.Add($h) } }
}

[System.IO.File]::WriteAllText($guard, ($out -join "`n"), $enc)
Ok "patched  : $guard"
Ok ("hook 1 after line " + ($close1 + 1) + ", hook 2 after line " + ($anchor2 + 1))
Say 'the kill switch is installed by the manager service itself'
Say 'fallback without a rebuild: create C:\ProgramData\AwgChain\no-inproc-lock'
Write-Host 'RESULT=OK'
