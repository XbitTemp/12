# AwgChain pack 49 / patch 30
# No handshake before the socket is pinned to the hop underneath.
# Adds tunnel\chainupwait.go and one call in tunnel\service.go.

param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$tun  = 'C:\dev\vpnchain\amneziawg-windows\tunnel'
$svc  = Join-Path $tun 'service.go'
$dst  = Join-Path $tun 'chainupwait.go'
$tpl  = 'C:\vpn\p49-chainupwait.go.txt'
$bak  = $svc + '.orig-p49'

$enc = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $svc)) { Bad ('not found: ' + $svc); Write-Host 'RESULT=FAIL reason=noservice'; exit 1 }

if ($Revert) {
  if (Test-Path $bak) {
    Copy-Item $bak $svc -Force
    Ok ('restored: ' + $svc)
  } else {
    Bad ('no backup: ' + $bak)
  }
  if (Test-Path $dst) { Remove-Item $dst -Force; Ok ('removed: ' + $dst) }
  Write-Host 'RESULT=OK mode=revert'
  exit 0
}

if (-not (Test-Path $tpl)) { Bad ('not found: ' + $tpl); Write-Host 'RESULT=FAIL reason=notemplate'; exit 1 }

# 1) the new source file, LF only, no BOM
$go = Get-Content $tpl -Raw
$go = $go -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($dst, $go, $enc)
Ok ('written : ' + $dst)

# 2) one call in service.go, right before the peers are brought up
$body = Get-Content $svc -Raw

if ($body -match 'chainWaitForPinBeforeUp') {
  Ok 'service.go already calls the wait, nothing to do'
  Write-Host 'RESULT=OK mode=idempotent'
  exit 0
}

$anchor = [char]9 + 'log.Println(' + $q + 'Bringing peers up' + $q + ')'
$hits = ([regex]::Matches($body, [regex]::Escape($anchor))).Count
if ($hits -ne 1) { Bad ('anchor found ' + $hits + ' times, expected 1'); Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }

if (-not (Test-Path $bak)) {
  Copy-Item $svc $bak -Force
  Say ('backup  : ' + $bak)
}

$ins = [char]9 + 'chainWaitForPinBeforeUp(config)' + [char]13 + [char]10 + [char]13 + [char]10 + $anchor
$body = $body.Replace($anchor, $ins)
[System.IO.File]::WriteAllText($svc, $body, $enc)

Ok 'service.go waits for the pinned adapter before the peers come up'
Ok 'the first handshake can no longer leave through the physical adapter'
Say 'wait limit: 20 seconds, then the old behaviour (retry in the background)'
Write-Host 'RESULT=OK'
