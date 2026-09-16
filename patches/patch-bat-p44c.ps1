# AwgChain pack 44c: the bat must never accept a broken pair name.
#
# What happened: fix-hop1conf.ps1 deleted the protected warpam-hop1.conf, and
# detect-pair.ps1 takes the pair name from exactly that file (step 3) or from
# an installed AwgChainTunnel$*-hop1 service (step 1). With the file gone and
# no services installed it returned junk, the bat squeezed it through
#   set "PAIR=%PAIR: =%"
# and ended up with a pair called " =". Hence the folder names " =-hop1.conf",
# " =.conf" and "The  =-hop1 adapter never appeared".
#
# This patch rewrites the tail of :detectpair so that:
#   - the name must match ^[A-Za-z0-9_][A-Za-z0-9_-]*$ or it is thrown away,
#   - the default is "warpam", not the pre-patch-14 "hop2-amnezia",
#   - "up" prints which pair it uses and where the name came from.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p44c.ps1 -Bat C:\vpn\awgchain.bat

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
$backup = $Bat + '.orig-p44c'

Say '==== AwgChain pack 44c: pair name in awgchain.bat ===='
Say ('file: ' + $Bat)

if (-not (Test-Path -LiteralPath $Bat)) {
  Bad 'awgchain.bat not found'
  Say 'RESULT=FAIL reason=nofile'
  exit 1
}

if ($Revert) {
  if (Test-Path -LiteralPath $backup) {
    Copy-Item -LiteralPath $backup -Destination $Bat -Force
    Ok 'restored the original bat'
    Say 'RESULT=REVERTED'
    exit 0
  }
  Bad 'no backup found'
  Say 'RESULT=FAIL reason=nobackup'
  exit 1
}

$text = [System.IO.File]::ReadAllText($Bat)
$changed = 0

# ---- 1. the pair name check ----
if ($text.Contains(':dpbadname')) {
  Say '[SKIP] the pair name is already checked'
} else {
  $old = 'set ' + $q + 'PAIR=%PAIR: =%' + $q + "`r`n" +
         'if not ' + $q + '%PAIR%' + $q + '==' + $q + $q + ' goto dpapply' + "`r`n" +
         'set ' + $q + 'PAIRSRC=fallback to the old console names' + $q + "`r`n" +
         'set ' + $q + 'PAIR=hop2-amnezia' + $q

  if ($text.IndexOf($old) -lt 0) {
    # try the same block with plain LF line ends
    $old = $old.Replace("`r`n", "`n")
  }
  if ($text.IndexOf($old) -lt 0) {
    Bad 'the :detectpair tail does not look like the expected block'
    Say 'RESULT=FAIL reason=anchor'
    exit 1
  }
  $nl = "`r`n"
  if ($old.Contains("`r`n") -eq $false) { $nl = "`n" }

  $new = @(
    'set ' + $q + 'PAIR=%PAIR: =%' + $q,
    'if ' + $q + '%PAIR%' + $q + '==' + $q + $q + ' goto dpdefault',
    'echo %PAIR%| findstr /R ' + $q + '^^[A-Za-z0-9_][A-Za-z0-9_-]*$' + $q + ' >nul',
    'if errorlevel 1 goto dpbadname',
    'goto dpapply',
    ':dpbadname',
    'echo note: ignoring a bad tunnel pair name from %PAIRSRC%',
    'set ' + $q + 'PAIR=' + $q,
    ':dpdefault',
    'set ' + $q + 'PAIRSRC=the built-in default name' + $q,
    'set ' + $q + 'PAIR=' + $Default + $q
  ) -join $nl

  if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $Bat -Destination $backup -Force
  }
  $text = $text.Replace($old, $new)
  $changed = $changed + 1
  Ok ('bad pair names are now rejected, the default is ' + $Default)
}

# ---- 2. show the pair in "up" ----
if ($text.Contains('echo pair            : %N2%')) {
  Say '[SKIP] up already prints the pair'
} else {
  $a = 'echo MTU             : hop1 %M1% / hop2 %M2%'
  if ($text.IndexOf($a) -lt 0) {
    Say '[WARN] could not find the MTU line in :cmd_up, skipping the report line'
  } else {
    $nl2 = "`r`n"
    if (-not $text.Contains("`r`n")) { $nl2 = "`n" }
    if (-not (Test-Path -LiteralPath $backup)) {
      Copy-Item -LiteralPath $Bat -Destination $backup -Force
    }
    $text = $text.Replace($a, $a + $nl2 + 'echo pair            : %N2% (hidden hop %N1%, from %PAIRSRC%)')
    $changed = $changed + 1
    Ok 'up now prints the pair name and where it came from'
  }
}

if ($changed -eq 0) {
  Say 'RESULT=OK'
  exit 0
}

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Bat, $text, $enc)
Say 'RESULT=OK'
Say 'Next: awgchain.bat up'
exit 0
