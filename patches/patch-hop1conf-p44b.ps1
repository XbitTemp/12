# AwgChain pack 44b: make-hop1-conf.ps1 must not fail on a protected old file.
#
# The script ends with a plain
#   [System.IO.File]::WriteAllText($Out, $text, $enc)
# which opens the EXISTING file for writing. The upstream client stores configs
# with a tight ACL of its own, so that open is refused even for an admin.
#
# This patch replaces that one line with a Write-Conf helper that:
#   1. clears read only / hidden / system attributes on the old file,
#   2. takes ownership and grants Administrators full control if needed,
#   3. deletes the old file,
#   4. writes the new text,
#   5. says what it had to do, so the log tells us the real story.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-hop1conf-p44b.ps1 -Script C:\vpn\make-hop1-conf.ps1

param(
  [string]$Script = 'C:\vpn\make-hop1-conf.ps1',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$Script = ('' + $Script).Trim().Trim($q)
$backup = $Script + '.orig-p44b'

Say '==== AwgChain pack 44b: make-hop1-conf.ps1 ===='
Say ('file: ' + $Script)

if (-not (Test-Path -LiteralPath $Script)) {
  Bad 'script not found'
  Say 'RESULT=FAIL reason=nofile'
  exit 1
}

if ($Revert) {
  if (Test-Path -LiteralPath $backup) {
    Copy-Item -LiteralPath $backup -Destination $Script -Force
    Ok 'restored the original script'
    Say 'RESULT=REVERTED'
    exit 0
  }
  Bad 'no backup found'
  Say 'RESULT=FAIL reason=nobackup'
  exit 1
}

$text = [System.IO.File]::ReadAllText($Script)

if ($text.Contains('function Write-Conf')) {
  Say '[SKIP] the script already writes the config the safe way'
  Say 'RESULT=OK'
  exit 0
}

$anchor = '[System.IO.File]::WriteAllText($Out, $text, $enc)'
$n = 0
$pos = 0
while (($pos = $text.IndexOf($anchor, $pos)) -ge 0) { $n = $n + 1; $pos = $pos + 1 }
if ($n -ne 1) {
  Bad ('the write line was found ' + $n + ' times, expected 1')
  Say 'RESULT=FAIL reason=anchor'
  exit 1
}

$tpl = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'p44b-writeconf.ps1.txt'
if (-not (Test-Path -LiteralPath $tpl)) {
  Bad 'p44b-writeconf.ps1.txt is missing next to this patch'
  Say 'RESULT=FAIL reason=notemplate'
  exit 1
}
$block = [System.IO.File]::ReadAllText($tpl)

if (-not (Test-Path -LiteralPath $backup)) {
  Copy-Item -LiteralPath $Script -Destination $backup -Force
}

$text = $text.Replace($anchor, $block)
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Script, $text, $enc)

Ok 'make-hop1-conf.ps1 now clears the old protected config before writing'
Say 'RESULT=OK'
Say 'Next: awgchain.bat up'
exit 0
