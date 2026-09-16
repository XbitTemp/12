# AwgChain pack 44: teach awgchain.bat to copy the guard through copy-guard.ps1
# so a locked file no longer ends the build with
#   [FAIL] A file could not be copied
# Also fixes the pack 42 root cause once more: every place that copies the
# guard is routed through the same helper, so no stale binary can sneak in.

param(
  [string]$Bat = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Read-Text($p) { return [System.IO.File]::ReadAllText($p) }
function Write-Text($p, $t) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p, $t, $enc)
}

if (('' + $Bat).Trim() -eq '') {
  $Bat = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'awgchain.bat'
}
$Bat = ('' + $Bat).Trim().Trim($q)

Write-Host '==== AwgChain pack 44: awgchain.bat guard copy ===='
Write-Host ('file: ' + $Bat)

if (-not (Test-Path -LiteralPath $Bat)) {
  Write-Host ('[FAIL] not found: ' + $Bat)
  Write-Host 'RESULT=FAIL reason=nobat'
  exit 1
}

$backup = $Bat + '.orig-p24'

if ($Revert) {
  if (Test-Path -LiteralPath $backup) {
    Copy-Item -LiteralPath $backup -Destination $Bat -Force
    Write-Host '[OK] awgchain.bat restored'
    Write-Host 'RESULT=REVERTED'
    exit 0
  }
  Write-Host '[FAIL] no .orig-p24 backup'
  Write-Host 'RESULT=FAIL reason=nobackup'
  exit 1
}

$text = Read-Text $Bat

if ($text.Contains('copy-guard.ps1')) {
  Write-Host '[SKIP] awgchain.bat already uses copy-guard.ps1'
  Write-Host 'RESULT=OK'
  exit 0
}

# copy /y "%CLIENT%\amd64\awgchain-guard.exe" "%GUARDEXE%" ...rest of line
$pattern = '(?m)^[ \t]*copy /y ' + $q + '%CLIENT%\\amd64\\awgchain-guard\.exe' + $q + '[ \t]+' + $q + '%GUARDEXE%' + $q + '.*$'
$hits = [regex]::Matches($text, $pattern)
Write-Host ('guard copy lines found: ' + $hits.Count)
if ($hits.Count -lt 1) {
  Write-Host '[FAIL] no guard copy line found, the bat must have changed'
  Write-Host 'RESULT=FAIL reason=noanchor'
  exit 1
}

$replacement = 'powershell -NoProfile -ExecutionPolicy Bypass -File ' + $q + '%HERE%copy-guard.ps1' + $q + ' -Src ' + $q + '%CLIENT%\amd64\awgchain-guard.exe' + $q + ' -Dst ' + $q + '%GUARDEXE%' + $q + ' >> ' + $q + '%LOG%' + $q + ' 2>&1'
$text = [regex]::Replace($text, $pattern, $replacement.Replace('$', '$$'))

if (-not (Test-Path -LiteralPath $backup)) {
  Copy-Item -LiteralPath $Bat -Destination $backup -Force
}
Write-Text $Bat $text

$check = Read-Text $Bat
if ($check.Contains('copy-guard.ps1')) {
  Write-Host '[OK] awgchain.bat now copies the guard with a retry'
  Write-Host 'RESULT=OK'
  exit 0
}
Write-Host '[FAIL] the change did not stick'
Write-Host 'RESULT=FAIL reason=write'
exit 1
