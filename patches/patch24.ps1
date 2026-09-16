# AwgChain patch 24 (pack 44)
# 1. The guard stop event gets a real security descriptor, so "ks off" works
#    from an elevated console without taskkill.
# 2. The manager stops re-arming a guard that dies at once three times.
# Written against the real sources in github.com/XbitTemp/12 (fork-sources).

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Core   = 'C:\dev\vpnchain\amneziawg-windows',
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

function Read-Text($path) { return [System.IO.File]::ReadAllText($path) }
function Write-Text($path, $text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}
function Backup-Once($path) {
  $b = $path + '.orig-p24'
  if (-not (Test-Path -LiteralPath $b)) { Copy-Item -LiteralPath $path -Destination $b -Force }
}
function Restore-Backup($path) {
  $b = $path + '.orig-p24'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Ok ('restored ' + $path)
    return $true
  }
  Say ('  no backup for ' + $path)
  return $false
}
function Tpl($name) {
  $p = Join-Path $Here $name
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  $t = Read-Text $p
  return $t.Replace("`r`n", "`n").TrimEnd("`n")
}
function One-Match($text, $pattern) {
  $m = [regex]::Matches($text, $pattern)
  return $m.Count
}

$stash    = Join-Path $Here 'guard-main.go'
$guardSrc = Join-Path $Client 'chainguard\main.go'
$mgrSrc   = Join-Path $Client 'manager\chainguard.go'

Say '==== AwgChain patch 24 (pack 44) ===='
Say ('client : ' + $Client)
Say ('here   : ' + $Here)

if ($Revert) {
  Say '-- revert --'
  Restore-Backup $stash    | Out-Null
  Restore-Backup $guardSrc | Out-Null
  Restore-Backup $mgrSrc   | Out-Null
  Say 'RESULT=REVERTED'
  exit 0
}

# ---------------------------------------------------------------- templates
$tGuardEvent = Tpl 'p44-guard-createevent.txt'
$tGuardSec   = Tpl 'p44-guard-sec.go.txt'
$tMgrEvent   = Tpl 'p44-mgr-createevent.txt'
$tMgrSec     = Tpl 'p44-mgr-sec.go.txt'
$tMgrHead    = Tpl 'p44-mgr-armhead.txt'
$tMgrWatch   = Tpl 'p44-mgr-watch.txt'
$tMgrReset   = Tpl 'p44-mgr-reset.txt'

if (($tGuardEvent -eq $null) -or ($tGuardSec -eq $null) -or ($tMgrEvent -eq $null) -or ($tMgrSec -eq $null) -or ($tMgrHead -eq $null) -or ($tMgrWatch -eq $null) -or ($tMgrReset -eq $null)) {
  Bad 'a p44-*.txt template is missing next to patch24.ps1'
  Say 'RESULT=FAIL reason=notemplate'
  exit 1
}

$winImport = '(?m)^[ \t]*' + $q + 'golang\.org/x/sys/windows' + $q + '[ \t]*$'
$unsafeIns = "`t" + $q + 'unsafe' + $q + "`n`n"

# ------------------------------------------------------- 1. the guard itself
$guardFiles = @($stash, $guardSrc)
$step1 = $true
foreach ($f in $guardFiles) {
  Say ('[1/3] guard source: ' + $f)
  if (-not (Test-Path -LiteralPath $f)) {
    Bad ('missing: ' + $f)
    $step1 = $false
    continue
  }
  $text = (Read-Text $f).Replace("`r`n", "`n")
  if ($text.Contains('stopEventSecurity')) {
    Say '  [SKIP] already carries the pack 44 event security'
    continue
  }
  $pat = '(?m)^[ \t]*return windows\.CreateEvent\(nil, 1, 0, name\)[ \t]*$'
  if ((One-Match $text $pat) -ne 1) {
    Bad '  the createStopEvent line was not found exactly once'
    $step1 = $false
    continue
  }
  if ((One-Match $text $winImport) -ne 1) {
    Bad '  the windows import line was not found exactly once'
    $step1 = $false
    continue
  }
  Backup-Once $f
  $text = [regex]::Replace($text, $pat, $tGuardEvent.Replace('$', '$$'))
  $text = [regex]::Replace($text, $winImport, ($unsafeIns + "`t" + $q + 'golang.org/x/sys/windows' + $q).Replace('$', '$$'))
  $text = $text.TrimEnd("`n") + "`n" + $tGuardSec + "`n"
  Write-Text $f $text
  Ok ('  patched ' + $f)
}

# ------------------------------------------------------------ 2. the manager
Say ('[2/3] manager source: ' + $mgrSrc)
$step2 = $true
if (-not (Test-Path -LiteralPath $mgrSrc)) {
  Bad ('missing: ' + $mgrSrc)
  $step2 = $false
} else {
  $m = (Read-Text $mgrSrc).Replace("`r`n", "`n")
  if ($m.Contains('chainStopEventSecurity')) {
    Say '  [SKIP] already carries the pack 44 manager side'
  } else {
    $pEvent = '(?m)^[ \t]*handle, err := windows\.CreateEvent\(nil, 1, 0, name\)[ \t]*$'
    $pHead  = '(?m)^[ \t]*if chainAutoGuardDisabled\(\) \{[ \t]*$'
    $pWatch = '(?s)[ \t]*go func\(started \*exec\.Cmd\) \{.*?\}\(cmd\)'
    $pReset = '(?s)[ \t]*chainStopWatch\(\)[ \t]*\n[ \t]*chainDisarmGuard\(\)'
    $bad = ''
    if ((One-Match $m $pEvent)   -ne 1) { $bad = 'createevent' }
    if ((One-Match $m $pHead)    -ne 1) { $bad = 'armhead' }
    if ((One-Match $m $pWatch)   -ne 1) { $bad = 'watchblock' }
    if ((One-Match $m $pReset)   -ne 1) { $bad = 'resetblock' }
    if ((One-Match $m $winImport) -ne 1) { $bad = 'import' }
    if ($bad -ne '') {
      Bad ('  anchor not unique: ' + $bad)
      $step2 = $false
    } else {
      Backup-Once $mgrSrc
      $m = [regex]::Replace($m, $pEvent, $tMgrEvent.Replace('$', '$$'))
      $m = [regex]::Replace($m, $pHead,  $tMgrHead.Replace('$', '$$'))
      $m = [regex]::Replace($m, $pWatch, ("`n" + $tMgrWatch).Replace('$', '$$'))
      $m = [regex]::Replace($m, $pReset, ("`n" + $tMgrReset).Replace('$', '$$'))
      $m = [regex]::Replace($m, $winImport, ($unsafeIns + "`t" + $q + 'golang.org/x/sys/windows' + $q).Replace('$', '$$'))
      $m = $m.TrimEnd("`n") + "`n" + $tMgrSec + "`n"
      Write-Text $mgrSrc $m
      Ok '  patched the manager'
    }
  }
}

# -------------------------------------------------------------- 3. the check
Say '[3/3] checking what is on disk now'
$step3 = $true
foreach ($f in @($stash, $guardSrc)) {
  if (Test-Path -LiteralPath $f) {
    $t = Read-Text $f
    if ($t.Contains('stopEventSecurity') -and $t.Contains($q + 'unsafe' + $q)) {
      Ok ('  event security present: ' + $f)
    } else {
      Bad ('  event security missing: ' + $f)
      $step3 = $false
    }
  } else {
    $step3 = $false
  }
}
if (Test-Path -LiteralPath $mgrSrc) {
  $t = Read-Text $mgrSrc
  if ($t.Contains('chainStopEventSecurity') -and $t.Contains('chainGuardGaveUp')) {
    Ok '  manager side present'
  } else {
    Bad '  manager side missing'
    $step3 = $false
  }
} else { $step3 = $false }

Say ''
if ($step1 -and $step2 -and $step3) {
  Say 'RESULT=OK'
  Say 'Next: awgchain.bat build then awgchain.bat install'
  exit 0
}
Say 'RESULT=FAIL reason=patch'
exit 1
