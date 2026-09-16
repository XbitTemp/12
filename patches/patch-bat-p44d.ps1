# AwgChain pack 44d: a MINIMAL, safe edit of awgchain.bat.
#
# Pack 44c tried to add new labels and jumps inside :detectpair. cmd.exe choked
# on it ("=" :dpdefault set "PAIRSRC=the was unexpected at this time."), so that
# patch must be reverted. Lesson: the checking belongs in PowerShell, not in
# the bat control flow.
#
# This patch only replaces single lines, it never adds labels or jumps:
#   1. set "PAIR=hop2-amnezia"   ->  set "PAIR=warpam"   (sane default)
#   2. after the MTU line in :cmd_up, one extra echo that prints the pair
#
# The actual name checking now lives in detect-pair.ps1 v2 from this pack.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p44d.ps1 -Bat C:\vpn\awgchain.bat

param(
  [string]$Bat = 'C:\vpn\awgchain.bat',
  [string]$Default = 'warpam',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$Bat = ('' + $Bat).Trim().Trim($q)
$backup = $Bat + '.orig-p44d'

Say '==== AwgChain pack 44d: awgchain.bat (minimal edit) ===='
Say ('file: ' + $Bat)

if (-not (Test-Path -LiteralPath $Bat)) {
  Bad 'awgchain.bat not found'
  Say 'RESULT=FAIL reason=nofile'
  exit 1
}

if ($Revert) {
  if (Test-Path -LiteralPath $backup) {
    Copy-Item -LiteralPath $backup -Destination $Bat -Force
    Ok 'restored the bat from the pack 44d backup'
    Say 'RESULT=REVERTED'
    exit 0
  }
  Bad 'no pack 44d backup found'
  Say 'RESULT=FAIL reason=nobackup'
  exit 1
}

$text = [System.IO.File]::ReadAllText($Bat)

# refuse to work on a bat that still carries the broken pack 44c block
if ($text.Contains(':dpbadname')) {
  Bad 'this bat still has the pack 44c block, revert it first:'
  Say '  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p44c.ps1 -Bat C:\vpn\awgchain.bat -Revert'
  Say 'RESULT=FAIL reason=pack44c'
  exit 1
}

$nl = "`r`n"
if (-not $text.Contains("`r`n")) { $nl = "`n" }
$changed = 0

if (-not (Test-Path -LiteralPath $backup)) {
  Copy-Item -LiteralPath $Bat -Destination $backup -Force
}

# ---- 1. the default pair name ----
$oldDefault = 'set ' + $q + 'PAIR=hop2-amnezia' + $q
$newDefault = 'set ' + $q + 'PAIR=' + $Default + $q
if ($text.Contains($newDefault)) {
  Say ('[SKIP] the default pair name is already ' + $Default)
} elseif ($text.Contains($oldDefault)) {
  $text = $text.Replace($oldDefault, $newDefault)
  $changed = $changed + 1
  Ok ('the default pair name is now ' + $Default)
} else {
  Say '[WARN] the old default line was not found, skipping step 1'
}

# ---- 2. show the pair in "up" ----
if ($text.Contains('echo pair            :')) {
  Say '[SKIP] up already prints the pair'
} else {
  $a = 'echo MTU             : hop1 %M1% / hop2 %M2%'
  if ($text.Contains($a)) {
    $text = $text.Replace($a, $a + $nl + 'echo pair            : %N2%   hidden hop: %N1%')
    $changed = $changed + 1
    Ok 'up now prints the pair name'
  } else {
    Say '[WARN] the MTU line in :cmd_up was not found, skipping step 2'
  }
}

if ($changed -gt 0) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Bat, $text, $enc)
}

# ---- 3. sanity check: no stray labels, the file still parses as before ----
$bad = 0
foreach ($line in [System.IO.File]::ReadAllLines($Bat)) {
  if ($line -match '^\s*:dp(badname|default)') { $bad = $bad + 1 }
}
if ($bad -gt 0) {
  Bad 'the bat still contains pack 44c labels'
  Say 'RESULT=FAIL reason=pack44c'
  exit 1
}

Say ('lines changed: ' + $changed)
Say 'RESULT=OK'
Say 'Next: awgchain.bat up'
exit 0
