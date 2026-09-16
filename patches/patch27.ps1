# AwgChain patch 27 (pack 46)
# Two fixes in the stress script:
#  1. It hung forever on "collecting diagnostics" because the diagnostics
#     called awgchain.exe /dumplog /tail, and /tail never returns: it follows
#     the log like a tail -f. Dropping /tail makes it dump once and exit.
#  2. If the tunnel services are not installed at all, every cycle waited the
#     full 60 seconds for nothing. Now the script says so and stops at once.
#
# powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch27.ps1
# powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch27.ps1 -Revert

param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$q = [char]34
$enc = New-Object System.Text.UTF8Encoding($false)

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$file = 'C:\vpn\stress-chain.ps1'
$bak  = $file + '.orig-p46'

if (-not (Test-Path -LiteralPath $file)) {
  Bad ('not found: ' + $file)
  Write-Host 'RESULT=FAIL reason=missing'
  exit 1
}

if ($Revert) {
  if (Test-Path -LiteralPath $bak) {
    Copy-Item -LiteralPath $bak -Destination $file -Force
    Ok ('restored from ' + $bak)
    Write-Host 'RESULT=REVERTED'
    exit 0
  }
  Bad 'no backup to restore'
  Write-Host 'RESULT=FAIL reason=nobackup'
  exit 1
}

$text = [System.IO.File]::ReadAllText($file)

if ($text.Contains('chain services are not installed')) {
  Ok 'already patched'
  Write-Host 'RESULT=OK'
  exit 0
}

if (-not (Test-Path -LiteralPath $bak)) {
  Copy-Item -LiteralPath $file -Destination $bak -Force
  Say ('backup         : ' + $bak)
}

$lines = [System.IO.File]::ReadAllLines($file)
$out = New-Object System.Collections.Generic.List[string]
$fixTail = 0
$fixGuard = 0

foreach ($line in $lines) {

  if ($line.Contains('/dumplog /tail')) {
    $out.Add($line.Replace('/dumplog /tail', '/dumplog'))
    $fixTail = $fixTail + 1
    continue
  }

  $out.Add($line)

  if (($fixGuard -eq 0) -and $line.Contains('==== stress v5 start')) {
    $out.Add('')
    $out.Add('# pack 46: a missing service is not worth a 60 second wait per cycle')
    $out.Add('if (((Svc-State $s1) -eq ' + $q + 'absent' + $q + ') -or ((Svc-State $s2) -eq ' + $q + 'absent' + $q + ')) {')
    $out.Add('  Note (' + $q + 'the chain services are not installed: ' + $q + ' + $s1 + ' + $q + ' / ' + $q + ' + $s2)')
    $out.Add('  Note (' + $q + 'raise the chain once with awgchain.bat up, then run the stress test again' + $q + ')')
    $out.Add('  Write-Host ' + $q + 'RESULT=FAIL reason=noservices' + $q)
    $out.Add('  exit 3')
    $out.Add('}')
    $fixGuard = 1
  }
}

if ($fixTail -eq 0) { Say 'note: no /dumplog /tail found, it may already be clean' }
if ($fixGuard -eq 0) {
  Bad 'anchor not found: ==== stress v5 start'
  Write-Host 'RESULT=FAIL reason=anchor'
  exit 1
}

$body = [string]::Join([char]13 + [char]10, $out.ToArray())
[System.IO.File]::WriteAllText($file, $body, $enc)

Ok ('diagnostics no longer follow the log forever, places fixed: ' + $fixTail)
Ok 'the stress test now stops at once when the services are absent'
Write-Host 'RESULT=OK'
exit 0
