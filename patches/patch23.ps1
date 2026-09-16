param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Here = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

if (('' + $Here).Trim() -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Here = ('' + $Here).Trim().Trim($q).Trim().TrimEnd('\')
$Client = ('' + $Client).Trim().Trim($q).Trim().TrimEnd('\')

function Write-Text($path, $text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Backup-Once($path, $suffix) {
  $bak = $path + $suffix
  if ((Test-Path $path) -and (-not (Test-Path $bak))) { Copy-Item $path $bak -Force }
}

function Restore-Backup($path, $suffix) {
  $bak = $path + $suffix
  if (Test-Path $bak) { Copy-Item $bak $path -Force; return $true }
  return $false
}

$sfx = '.orig-p23'
$stash    = Join-Path $Here 'guard-main.go'
$template = Join-Path $Here 'p42-guard-main.go.txt'
$guardSrc = Join-Path $Client 'chainguard\main.go'
$mgrSrc   = Join-Path $Client 'manager\chainguard.go'

Say '=================================================='
Say 'AwgChain patch 23 - the build stash gets the new'
Say 'guard source, so a rebuild stops undoing patch 22'
Say ('date   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('client : ' + $Client)
Say ('here   : ' + $Here)
Say '=================================================='

if ($Revert) {
  $a = Restore-Backup $stash    $sfx
  $b = Restore-Backup $guardSrc $sfx
  $c = Restore-Backup $mgrSrc   $sfx
  if ($a) { Ok 'guard-main.go was restored from the backup' } else { Say '[SKIP] no backup for guard-main.go' }
  if ($b) { Ok 'chainguard\main.go was restored from the backup' } else { Say '[SKIP] no backup for chainguard\main.go' }
  if ($c) { Ok 'manager\chainguard.go was restored from the backup' } else { Say '[SKIP] no backup for manager\chainguard.go' }
  Say ''
  Say 'Now rebuild and reinstall: awgchain.bat build   then   awgchain.bat install'
  Say 'RESULT=OK'
  exit 0
}

if (-not (Test-Path $template)) { Bad ('the template is missing: ' + $template); Say 'RESULT=FAIL reason=notemplate'; exit 1 }
if (-not (Test-Path $mgrSrc))   { Bad ('not found: ' + $mgrSrc);             Say 'RESULT=FAIL reason=nomanager'; exit 1 }
if (-not (Test-Path $stash))    { Bad ('not found: ' + $stash);              Say 'RESULT=FAIL reason=nostash';   exit 1 }

$new = [System.IO.File]::ReadAllText($template)
if ($new -notmatch 'orphangrace') { Bad 'the template does not mention orphangrace, it is the wrong file'; Say 'RESULT=FAIL reason=badtemplate'; exit 1 }
$new = $new -replace "`r`n", "`n"

Say 'step 1 of 3: the build stash C:\vpn\guard-main.go'
Backup-Once $stash $sfx
Say ('a copy of the original is kept as guard-main.go' + $sfx)
Write-Text $stash $new
$chk = [System.IO.File]::ReadAllText($stash)
if ($chk -match 'orphangrace') { Ok 'guard-main.go in the stash now carries the new guard' }
else { Bad 'the stash was not written'; Say 'RESULT=FAIL reason=stashwrite'; exit 1 }

Say 'step 2 of 3: the working copy chainguard\main.go'
if (-not (Test-Path (Join-Path $Client 'chainguard'))) { New-Item -ItemType Directory -Path (Join-Path $Client 'chainguard') | Out-Null }
Backup-Once $guardSrc $sfx
Write-Text $guardSrc $new
$chk2 = [System.IO.File]::ReadAllText($guardSrc)
if ($chk2 -match 'orphangrace') { Ok 'chainguard\main.go now carries the new guard' }
else { Bad 'the working copy was not written'; Say 'RESULT=FAIL reason=srcwrite'; exit 1 }

Say 'step 3 of 3: the manager tells the guard its own process id'
$mgr = [System.IO.File]::ReadAllText($mgrSrc)
if ($mgr -match '-mgrpid') {
  Ok 'manager\chainguard.go already passes -mgrpid'
} else {
  Backup-Once $mgrSrc $sfx
  Say ('a copy of the original is kept as chainguard.go' + $sfx)
  $anchor = '(?m)^([ \t]*)' + $q + '-logfile' + $q + ', filepath\.Join\(chainStateDir\(\), ' + $q + 'guard-auto-log\.txt' + $q + '\),[ \t]*$'
  $m = [regex]::Match($mgr, $anchor)
  if (-not $m.Success) { Bad 'the -logfile argument line was not found in manager\chainguard.go'; Say 'RESULT=FAIL reason=noanchor'; exit 1 }
  $pad = $m.Groups[1].Value
  $add = $m.Value + "`n" + $pad + $q + '-mgrpid' + $q + ', strconv.Itoa(os.Getpid()),' + "`n" + $pad + $q + '-orphangrace' + $q + ', ' + $q + '120' + $q + ','
  $mgr = $mgr.Remove($m.Index, $m.Length).Insert($m.Index, $add)

  $im = [regex]::Match($mgr, '(?m)^import \($')
  if ($im.Success) {
    $ins = ''
    if ($mgr -notmatch ('(?m)^[ \t]*' + $q + 'os' + $q + '[ \t]*$')) { $ins = $ins + "`n`t" + $q + 'os' + $q }
    if ($mgr -notmatch ('(?m)^[ \t]*' + $q + 'strconv' + $q + '[ \t]*$')) { $ins = $ins + "`n`t" + $q + 'strconv' + $q }
    if ($ins -ne '') { $mgr = $mgr.Insert($im.Index + $im.Length, $ins) }
  }

  Write-Text $mgrSrc ($mgr -replace "`r`n", "`n")
  $chk3 = [System.IO.File]::ReadAllText($mgrSrc)
  if ($chk3 -match '-mgrpid' -and $chk3 -match 'orphangrace') { Ok 'manager\chainguard.go passes -mgrpid and -orphangrace 120' }
  else { Bad 'the manager edit did not stick'; Say 'RESULT=FAIL reason=mgrwrite'; exit 1 }
}

Say ''
Say 'What to do next:'
Say 'awgchain.bat build'
Say 'awgchain-guardchk.bat        the guard must report -mgrpid'
Say 'awgchain.bat install'
Say 'awgchain.bat gui'
Say 'awgchain.bat stress 10'
Say ''
Say 'If guardchk says the guard is stale, do not run the stress test,'
Say 'send its output to the chat instead.'
Say 'RESULT=OK'
exit 0
