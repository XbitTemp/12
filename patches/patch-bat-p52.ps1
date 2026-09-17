# AwgChain patch-bat-p52 (pack 52)
# One line replaced in awgchain.bat: the 'up' command says out loud that it
# raises the chain without the manager, so no kill switch is armed.
# Backup: awgchain.bat.orig-p52 ;  rollback:  -Revert
# Rule of this project: line replacement only, no new labels and no goto.

param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($m) { Write-Host $m }
function Ok($m)  { Write-Host "[OK] $m" }
function Bad($m) { Write-Host "[FAIL] $m" }

$bat    = 'C:\vpn\awgchain.bat'
$backup = $bat + '.orig-p52'
$enc    = New-Object System.Text.UTF8Encoding($false)

$anchor = 'echo pair            : %N2%   hidden hop: %N1%'
$warn   = 'echo kill switch     : none - this command bypasses the manager, raise the chain from the app window to be protected'

if (-not (Test-Path $bat)) { Bad "not found: $bat"; Write-Host 'RESULT=FAIL reason=nofile'; exit 1 }

if ($Revert) {
	if (-not (Test-Path $backup)) { Bad "no backup: $backup"; Write-Host 'RESULT=FAIL reason=nobackup'; exit 1 }
	Copy-Item $backup $bat -Force
	Ok "restored : $bat"
	Write-Host 'RESULT=REVERTED'
	exit 0
}

$text = [System.IO.File]::ReadAllText($bat)

if ($text.Contains('this command bypasses the manager')) {
	Ok 'the warning is already there, nothing to do'
	Write-Host 'RESULT=OK'
	exit 0
}

if (-not $text.Contains($anchor)) { Bad 'anchor not found (pair line in :cmd_up)'; Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }

if (-not (Test-Path $backup)) {
	[System.IO.File]::WriteAllText($backup, $text, $enc)
	Say "backup   : $backup"
}

$eol = [char]13 + [char]10
$text = $text.Replace($anchor, $anchor + $eol + $warn)
[System.IO.File]::WriteAllText($bat, $text, $enc)

Ok 'awgchain.bat: the up command now warns that it leaves the machine unlocked'
Write-Host 'RESULT=OK'
exit 0
