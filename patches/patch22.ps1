# AwgChain patch 22 - the kill switch does not outlive the manager
#
# Pack 42a: the only change against the first patch22.ps1 is that a dead line
# with escaped quotes is gone. That line was never used, but PowerShell parsed
# the whole file before running it, so nothing ran at all:
#   Unexpected token '-logfile' in expression or statement.
#
# The problem this patch fixes (report of 2026-09-16):
#   the chain is up, the program is closed -> the internet is gone and stays
#   gone until awgchain-guard.exe is killed by hand.
#
# Two changes:
#   1. chainguard\main.go     the guard watches the manager process id given
#                             with -mgrpid. When the manager disappears AND a
#                             hop is missing, the kill switch is removed after
#                             -orphangrace seconds (default 120). While the
#                             chain is intact the guard keeps holding, because
#                             traffic is still tunnelled and nothing can leak.
#   2. manager\chainguard.go  chainArmGuard passes -mgrpid <own pid> and
#                             -orphangrace 120 when it starts the guard.
#
# Files are backed up once as <name>.orig-p22. Undo with -Revert. Re-running
# is safe.

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Core = 'C:\dev\vpnchain\amneziawg-windows',
  [string]$Here = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

# A trailing backslash inside a quoted cmd argument escapes the closing quote.
$Here = ('' + $Here).Trim().Trim('"').Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Client = ('' + $Client).Trim().Trim('"').Trim().TrimEnd('\')
$Core = ('' + $Core).Trim().Trim('"').Trim().TrimEnd('\')

$script:fails = 0

function Say([string]$m) { Write-Host $m }
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Skip([string]$m) { Write-Host ('[SKIP] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Write-Go([string]$path, [string]$text) {
  $lf = ($text -replace "`r`n", "`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $lf, $enc)
}

function Backup-Once([string]$path) {
  $b = $path + '.orig-p22'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Say ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p22'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Ok ($label + ' was restored from the backup')
  } else {
    Say ('  no backup for ' + $label + ', leaving it alone')
  }
}

$guardMain = Join-Path $Client 'chainguard\main.go'
$mgrGuard = Join-Path $Client 'manager\chainguard.go'
$template = Join-Path $Here 'p42-guard-main.go.txt'

Say '=================================================='
Say 'AwgChain patch 22 - the guard lets go when nobody'
Say '                    is left to repair the chain'
Say ('date   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('client : ' + $Client)
Say '=================================================='

if ($Revert) {
  Restore-Backup $guardMain 'chainguard\main.go'
  Restore-Backup $mgrGuard 'manager\chainguard.go'
  Say ''
  Say 'Now rebuild and reinstall: awgchain.bat build   then   awgchain.bat install'
  Say 'RESULT=OK'
  exit 0
}

if (-not (Test-Path -LiteralPath $guardMain)) { Bad ('not found: ' + $guardMain) }
if (-not (Test-Path -LiteralPath $mgrGuard)) { Bad ('not found: ' + $mgrGuard) }
if (-not (Test-Path -LiteralPath $template)) { Bad 'not found next to awgchain.bat: p42-guard-main.go.txt' }
if ($script:fails -gt 0) {
  Say ''
  Say 'RESULT=FAIL reason=missing'
  exit 1
}

# ---------------------------------------------- 1. chainguard\main.go ---
Say 'step 1 of 2: chainguard\main.go watches the manager'

$new = [System.IO.File]::ReadAllText($template)
if ($new -notmatch 'orphangrace') {
  Bad 'the template does not carry the orphan handling, the pack is broken'
} else {
  $cur = [System.IO.File]::ReadAllText($guardMain)
  if ($cur -eq ($new -replace "`r`n", "`n")) {
    Skip 'chainguard\main.go is already the pack 42 version'
  } else {
    Backup-Once $guardMain
    Write-Go $guardMain $new
    Ok 'chainguard\main.go now releases an orphaned kill switch'
  }
}

# ------------------------------------------- 2. manager\chainguard.go ---
Say 'step 2 of 2: the manager tells the guard its own process id'

$text = [System.IO.File]::ReadAllText($mgrGuard)

if ($text -match '-mgrpid') {
  Skip 'manager\chainguard.go already passes -mgrpid'
} else {
  $rx = New-Object System.Text.RegularExpressions.Regex('(?m)^[ \t]*"-logfile", filepath\.Join\(chainStateDir\(\), "guard-auto-log\.txt"\),[ \t]*$')
  $m = $rx.Match($text)
  if (-not $m.Success) {
    Bad 'could not find the guard argument list in manager\chainguard.go'
  } else {
    $q = [char]34
    $line1 = "`t`t" + $q + '-mgrpid' + $q + ', strconv.Itoa(os.Getpid()),'
    $line2 = "`t`t" + $q + '-orphangrace' + $q + ', ' + $q + '120' + $q + ','
    $ins = $m.Value + "`n" + $line1 + "`n" + $line2
    $text = $text.Substring(0, $m.Index) + $ins + $text.Substring($m.Index + $m.Length)

    if ($text -notmatch '(?m)^[ \t]*"strconv"[ \t]*$') {
      $irx = New-Object System.Text.RegularExpressions.Regex('(?m)^([ \t]*)"strings"[ \t]*$')
      $im = $irx.Match($text)
      if (-not $im.Success) {
        Bad 'could not find the import block of manager\chainguard.go'
      } else {
        $indent = $im.Groups[1].Value
        $text = $text.Substring(0, $im.Index) + $indent + $q + 'strconv' + $q + "`n" + $text.Substring($im.Index)
      }
    }

    if ($script:fails -eq 0) {
      Backup-Once $mgrGuard
      Write-Go $mgrGuard $text
      Ok 'manager\chainguard.go passes -mgrpid and -orphangrace 120'
    }
  }
}

Say ''
if ($script:fails -gt 0) {
  Say 'RESULT=FAIL'
  exit 1
}
Say 'What to do next:'
Say '  awgchain.bat build'
Say '  awgchain.bat install'
Say '  awgchain.bat gui       raise the chain, then close the program'
Say '  the internet comes back on its own within about two minutes'
Say '  awgchain.bat ksstop    removes the kill switch at once'
Say 'RESULT=OK'
exit 0
