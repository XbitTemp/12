# AwgChain patch 28 (pack 47)
# The hop above now wakes the hop underneath.
#
# Pack 45 works: the log shows the tunnel service waiting instead of dying.
# What is missing is the start of hop 1 when only the service of hop 2 is
# started (autostart, the button in the window, sc start). This patch replaces
# tunnel\chainpinwait.go with a version that asks the service control manager
# to start AwgChainTunnel$<pin interface> while it waits.
#
# powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch28.ps1
# powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch28.ps1 -Revert

param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UTF8Encoding($false)

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$roots = @(
  'C:\dev\vpnchain\amneziawg-windows\tunnel',
  'C:\dev\vpnchain\amneziawg-windows-client\tunnel'
)

$tunnel = ''
foreach ($r in $roots) {
  if (Test-Path -LiteralPath (Join-Path $r 'pinendpoint.go')) { $tunnel = $r; break }
}

if ($tunnel -eq '') {
  Bad 'tunnel folder with pinendpoint.go not found'
  Write-Host 'RESULT=FAIL reason=notunnel'
  exit 1
}

Say ('tunnel folder  : ' + $tunnel)

$target = Join-Path $tunnel 'chainpinwait.go'
$bak = $target + '.orig-p47'

if ($Revert) {
  if (Test-Path -LiteralPath $bak) {
    Copy-Item -LiteralPath $bak -Destination $target -Force
    Ok ('restored from ' + $bak)
    Write-Host 'RESULT=REVERTED'
    exit 0
  }
  Bad 'no backup to restore'
  Write-Host 'RESULT=FAIL reason=nobackup'
  exit 1
}

$template = 'C:\vpn\p47-chainpinwait.go.txt'
if (-not (Test-Path -LiteralPath $template)) {
  Bad ('template not found: ' + $template)
  Write-Host 'RESULT=FAIL reason=notemplate'
  exit 1
}

if (-not (Test-Path -LiteralPath $target)) {
  Bad ('pack 45 file missing: ' + $target + ' - apply patch26 first')
  Write-Host 'RESULT=FAIL reason=nopack45'
  exit 1
}

if (-not (Test-Path -LiteralPath $bak)) {
  Copy-Item -LiteralPath $target -Destination $bak -Force
  Say ('backup         : ' + $bak)
}

$body = [System.IO.File]::ReadAllText($template)
$body = $body.Replace([char]13 + [char]10, [char]10)
[System.IO.File]::WriteAllText($target, $body, $enc)

if ($body.Contains('chainStartHopBelow')) {
  Ok ('rewritten      : ' + $target)
  Ok 'while waiting, the tunnel now starts the service of the hop underneath'
  Write-Host 'RESULT=OK'
  exit 0
}

Bad 'the template does not contain chainStartHopBelow'
Write-Host 'RESULT=FAIL reason=badtemplate'
exit 1
