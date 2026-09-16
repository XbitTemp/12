param([switch]$Revert)
$ErrorActionPreference = 'Continue'
$q = [char]34
function Say($m) { Write-Host $m }
function Ok($m)  { Write-Host ('[OK] ' + $m) }
function Bad($m) { Write-Host ('[FAIL] ' + $m) }

$file = 'C:\dev\vpnchain\amneziawg-windows\tunnel\chainupwait.go'
$bak  = $file + '.orig-p50'
$enc  = New-Object System.Text.UTF8Encoding($false)
$mark = 'chainPinRoutes(config, true)'
$anchorText = 'the handshake may go out'

if (-not (Test-Path $file)) {
	Bad ('not found: ' + $file)
	Say 'apply patch30 (pack 49) first'
	Write-Host 'RESULT=FAIL reason=nofile'
	exit 1
}

if ($Revert) {
	if (Test-Path $bak) {
		$old = [System.IO.File]::ReadAllText($bak)
		[System.IO.File]::WriteAllText($file, $old, $enc)
		Ok ('restored : ' + $file)
		Write-Host 'RESULT=REVERTED'
		exit 0
	}
	Bad ('no backup: ' + $bak)
	Write-Host 'RESULT=FAIL reason=nobackup'
	exit 1
}

$body = [System.IO.File]::ReadAllText($file)
$body = $body -replace "`r`n", "`n"

if ($body.Contains($mark)) {
	Ok 'already patched, nothing to do'
	Write-Host 'RESULT=OK'
	exit 0
}

$lines = $body.Split([char]10)
$hit = -1
for ($i = 0; $i -lt $lines.Length; $i++) {
	if ($lines[$i].Contains($anchorText)) {
		if ($hit -ge 0) {
			Bad 'the anchor line is not unique'
			Write-Host 'RESULT=FAIL reason=anchor'
			exit 1
		}
		$hit = $i
	}
}

if ($hit -lt 0) {
	Bad ('anchor not found: ' + $anchorText)
	Write-Host 'RESULT=FAIL reason=anchor'
	exit 1
}

$indent = ''
$m = [regex]::Match($lines[$hit], '^[\t ]*')
if ($m.Success) { $indent = $m.Value }

$ins = @()
$ins += ($indent + $mark)

$out = @()
for ($i = 0; $i -lt $lines.Length; $i++) {
	$out += $lines[$i]
	if ($i -eq $hit) { $out += $ins }
}

if (-not (Test-Path $bak)) {
	[System.IO.File]::WriteAllText($bak, $body, $enc)
	Say ('backup  : ' + $bak)
}

$new = [string]::Join([string][char]10, $out)
[System.IO.File]::WriteAllText($file, $new, $enc)

Ok ('patched : ' + $file)
Ok ('anchor line ' + ($hit + 1) + ', one line added')
Ok 'the route to the hop 2 endpoint is now pinned BEFORE the peers come up'
Say 'so the very first handshake cannot use the physical adapter even for a few ms'
Write-Host 'RESULT=OK'
