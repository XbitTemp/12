# AwgChain patch 33 (pack 52)
# The in-process kill switch is re-armed after every successful repair.
#   1. adds manager\chainrelock.go
#   2. one line replaced in manager\chainguard.go (chainRepair success branch)
# Backup: manager\chainguard.go.orig-p52 ;  rollback:  -Revert

param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($m) { Write-Host $m }
function Ok($m)  { Write-Host "[OK] $m" }
function Bad($m) { Write-Host "[FAIL] $m" }

$mgr    = 'C:\dev\vpnchain\amneziawg-windows-client\manager'
$guard  = Join-Path $mgr 'chainguard.go'
$relock = Join-Path $mgr 'chainrelock.go'
$backup = $guard + '.orig-p52'
$tpl    = Join-Path $PSScriptRoot 'p52-chainrelock.go.txt'
$enc    = New-Object System.Text.UTF8Encoding($false)

$marker = 'chainRearmLockAfterRepair(leaf)'
$oldLog = 'the kill switch follows the new interfaces by itself'

if (-not (Test-Path $guard)) { Bad "not found: $guard"; Write-Host 'RESULT=FAIL reason=nofile'; exit 1 }

if ($Revert) {
	if (-not (Test-Path $backup)) { Bad "no backup: $backup"; Write-Host 'RESULT=FAIL reason=nobackup'; exit 1 }
	Copy-Item $backup $guard -Force
	if (Test-Path $relock) { Remove-Item $relock -Force }
	Ok "restored : $guard"
	Ok 'chainrelock.go removed'
	Write-Host 'RESULT=REVERTED'
	exit 0
}

if (-not (Test-Path $tpl)) { Bad "not found: $tpl"; Write-Host 'RESULT=FAIL reason=notemplate'; exit 1 }

# --- 1. the new file -------------------------------------------------------
$body = [System.IO.File]::ReadAllText($tpl)
$body = $body -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($relock, $body, $enc)
Ok "written  : $relock"

# --- 2. the repair hook ----------------------------------------------------
$text = [System.IO.File]::ReadAllText($guard)
$text = $text -replace "`r`n", "`n"

if ($text.Contains($marker)) {
	Ok 'chainguard.go already calls the re-arm, nothing to do'
	Write-Host 'RESULT=OK'
	exit 0
}

if (-not (Test-Path $backup)) {
	[System.IO.File]::WriteAllText($backup, $text, $enc)
	Say "backup   : $backup"
}

$lines = $text.Split("`n")
$hit = -1
for ($i = 0; $i -lt $lines.Length; $i++) {
	if ($lines[$i].Contains($oldLog)) { $hit = $i; break }
}
if ($hit -lt 0) { Bad 'anchor not found (repair success log line)'; Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }

$tab = [char]9
$newLog = $tab + $tab + $tab + 'log.Printf(' + $q + '[AwgChain] Repair: the chain is back up after %d seconds, re-arming the kill switch on the new interfaces' + $q + ', int(time.Since(started).Seconds()))'
$call   = $tab + $tab + $tab + 's.chainRearmLockAfterRepair(leaf)'

$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Length; $i++) {
	if ($i -eq $hit) {
		$out.Add($newLog)
		$out.Add($call)
	} else {
		$out.Add($lines[$i])
	}
}

[System.IO.File]::WriteAllText($guard, ($out -join "`n"), $enc)
Ok ("patched  : " + $guard + " (line " + ($hit + 1) + ")")
Write-Host 'RESULT=OK'
exit 0
