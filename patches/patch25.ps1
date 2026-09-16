# AwgChain patch 25 (pack 44a)
#
# Pack 44 gave the stop event a real security descriptor, and it worked: the
# error changed from "Access is denied" to
#   Cannot create a file when that file already exists.
# That is ERROR_ALREADY_EXISTS (183). CreateEvent returns a perfectly usable
# handle together with that code when the event is already there, which is the
# normal case for -stop: the guard created it, we only signal it. The code
# treated any non nil error as a failure, so the signal was never sent.
# Patch 25 accepts ERROR_ALREADY_EXISTS as success on both sides.

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Here   = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$q = [char]34

$Here = ('' + $Here).Trim().Trim($q).Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Client = ('' + $Client).Trim().Trim($q).TrimEnd('\')

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] '   + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }
function Read-Text($p) { return [System.IO.File]::ReadAllText($p) }
function Write-Text($p, $t) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p, $t, $enc)
}
function Backup-Once($p) {
  $b = $p + '.orig-p25'
  if (-not (Test-Path -LiteralPath $b)) { Copy-Item -LiteralPath $p -Destination $b -Force }
}
function Restore-Backup($p) {
  $b = $p + '.orig-p25'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $p -Force
    Ok ('restored ' + $p)
  } else {
    Say ('  no backup for ' + $p)
  }
}
function Tpl($name) {
  $p = Join-Path $Here $name
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  $t = Read-Text $p
  return $t.Replace("`r`n", "`n").TrimEnd("`n")
}

$stash    = Join-Path $Here 'guard-main.go'
$guardSrc = Join-Path $Client 'chainguard\main.go'
$mgrSrc   = Join-Path $Client 'manager\chainguard.go'

Say '==== AwgChain patch 25 (pack 44a) ===='
Say ('client : ' + $Client)
Say ('here   : ' + $Here)

if ($Revert) {
  Say '-- revert --'
  Restore-Backup $stash
  Restore-Backup $guardSrc
  Restore-Backup $mgrSrc
  Say 'RESULT=REVERTED'
  exit 0
}

$tGuard = Tpl 'p44a-guard-createevent.txt'
$tMgr   = Tpl 'p44a-mgr-createevent.txt'
if (($tGuard -eq $null) -or ($tMgr -eq $null)) {
  Bad 'a p44a-*.txt template is missing next to patch25.ps1'
  Say 'RESULT=FAIL reason=notemplate'
  exit 1
}

$pGuard = '(?m)^[ \t]*return windows\.CreateEvent\(stopEventSecurity\(\), 1, 0, name\)[ \t]*$'
$pMgr   = '(?m)^[ \t]*handle, err := windows\.CreateEvent\(chainStopEventSecurity\(\), 1, 0, name\)[ \t]*$'

$allOk = $true

foreach ($f in @($stash, $guardSrc)) {
  Say ('[1/2] guard source: ' + $f)
  if (-not (Test-Path -LiteralPath $f)) {
    Bad ('missing: ' + $f)
    $allOk = $false
    continue
  }
  $t = (Read-Text $f).Replace("`r`n", "`n")
  if ($t.Contains('ERROR_ALREADY_EXISTS')) {
    Say '  [SKIP] already tolerates ERROR_ALREADY_EXISTS'
    continue
  }
  $n = ([regex]::Matches($t, $pGuard)).Count
  if ($n -ne 1) {
    Bad ('  the pack 44 CreateEvent line was found ' + $n + ' times, expected 1. Apply patch 24 first.')
    $allOk = $false
    continue
  }
  Backup-Once $f
  $t = [regex]::Replace($t, $pGuard, $tGuard.Replace('$', '$$'))
  Write-Text $f $t
  Ok ('  patched ' + $f)
}

Say ('[2/2] manager source: ' + $mgrSrc)
if (-not (Test-Path -LiteralPath $mgrSrc)) {
  Bad ('missing: ' + $mgrSrc)
  $allOk = $false
} else {
  $m = (Read-Text $mgrSrc).Replace("`r`n", "`n")
  if ($m.Contains('ERROR_ALREADY_EXISTS')) {
    Say '  [SKIP] already tolerates ERROR_ALREADY_EXISTS'
  } else {
    $n = ([regex]::Matches($m, $pMgr)).Count
    if ($n -ne 1) {
      Bad ('  the pack 44 CreateEvent line was found ' + $n + ' times, expected 1. Apply patch 24 first.')
      $allOk = $false
    } else {
      Backup-Once $mgrSrc
      $m = [regex]::Replace($m, $pMgr, $tMgr.Replace('$', '$$'))
      Write-Text $mgrSrc $m
      Ok '  patched the manager'
    }
  }
}

Say ''
if ($allOk) {
  Say 'RESULT=OK'
  Say 'Next: awgchain.bat build then awgchain.bat install'
  exit 0
}
Say 'RESULT=FAIL reason=patch'
exit 1
