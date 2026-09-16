# AwgChain patch 29 (pack 48)
# Fixes the stress test measurement: the egress probe reused one TCP connection
# opened while the chain was down, so every probe reported the ISP address.
# Now each probe runs curl.exe in a fresh process without keep-alive, and the
# leak address never counts as a working chain.
param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($m) { Write-Host $m }
function Ok($m)  { Write-Host ('[OK] ' + $m) }
function Bad($m) { Write-Host ('[FAIL] ' + $m) }

$file = 'C:\vpn\stress-chain.ps1'
$bak  = 'C:\vpn\stress-chain.ps1.orig-p48'

if (-not (Test-Path -LiteralPath $file)) {
  Bad ('not found: ' + $file)
  Write-Host 'RESULT=FAIL reason=nostress'
  exit 1
}

if ($Revert) {
  if (-not (Test-Path -LiteralPath $bak)) {
    Bad ('no backup: ' + $bak)
    Write-Host 'RESULT=FAIL reason=nobackup'
    exit 1
  }
  Copy-Item -LiteralPath $bak -Destination $file -Force
  Ok 'stress-chain.ps1 restored from the backup'
  Write-Host 'RESULT=REVERTED'
  exit 0
}

if (-not (Test-Path -LiteralPath $bak)) {
  Copy-Item -LiteralPath $file -Destination $bak -Force
  Say ('backup         : ' + $bak)
} else {
  Say ('backup exists  : ' + $bak)
}

$enc  = New-Object System.Text.UTF8Encoding($false)
$body = [System.IO.File]::ReadAllText($file)
$done = 0

# 1. probe with curl.exe, fresh process, no keep-alive
$old1 = '      $r = Invoke-RestMethod -Uri ' + [char]39 + 'https://api.ipify.org?format=json' + [char]39 + ' -TimeoutSec 8 -ErrorAction Stop'
$new1 = '      $out = & curl.exe -s --max-time 8 --no-keepalive --http1.1 https://api.ipify.org'
if ($body.Contains($new1)) {
  Say 'probe already uses curl.exe'
} elseif ($body.Contains($old1)) {
  $body = $body.Replace($old1, $new1)
  $done = $done + 1
} else {
  Bad 'the Invoke-RestMethod line was not found'
  Write-Host 'RESULT=FAIL reason=noprobe'
  exit 1
}

$old2 = '      if ((' + [char]39 + [char]39 + ' + $r.ip).Trim() -ne ' + [char]39 + [char]39 + ') { return (' + [char]39 + [char]39 + ' + $r.ip).Trim() }'
$new2 = '      $ip0 = (' + [char]39 + [char]39 + ' + $out).Trim(); if ($ip0 -match ' + [char]39 + '^[0-9][0-9.]+$' + [char]39 + ') { return $ip0 }'
if ($body.Contains($new2)) {
  Say 'probe result parsing already patched'
} elseif ($body.Contains($old2)) {
  $body = $body.Replace($old2, $new2)
  $done = $done + 1
} else {
  Bad 'the probe result line was not found'
  Write-Host 'RESULT=FAIL reason=noparse'
  exit 1
}

# 2. the leak address never counts as a working chain
$old3 = '        if (($expect -eq ' + [char]39 + [char]39 + ') -or ($ip -eq $expect)) {'
$new3 = '        $good = $false; if ($expect -ne ' + [char]39 + [char]39 + ') { $good = ($ip -eq $expect) } else { $good = ($ip -ne $leakAddr) }; if ($good) {'
if ($body.Contains($new3)) {
  Say 'the leak address is already treated as not ready'
} elseif ($body.Contains($old3)) {
  $body = $body.Replace($old3, $new3)
  $done = $done + 1
} else {
  Bad 'the Wait-Usable decision line was not found'
  Write-Host 'RESULT=FAIL reason=nowait'
  exit 1
}

if ($done -gt 0) {
  [System.IO.File]::WriteAllText($file, $body, $enc)
}

Ok ('lines changed  : ' + $done)
Ok 'the egress probe no longer reuses the connection opened while the chain was down'
Ok 'the leak address is never accepted as a working chain'

if (-not (Test-Path -LiteralPath 'C:\vpn\logs')) {
  New-Item -ItemType Directory -Path 'C:\vpn\logs' -Force | Out-Null
  Ok 'recreated C:\vpn\logs'
}

Write-Host 'RESULT=OK'
