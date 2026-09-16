# AwgChain pack 44e: make-hop2-conf.ps1 must clear the protected old config too.
#
# Pack 44b fixed make-hop1-conf.ps1 only, so "up" got one step further and then
# failed on the second config:
#   Exception calling "WriteAllText" ... "Access to the path
#   'C:\Program Files\AwgChain\Data\Configurations\warpam.conf' is denied."
# Same cause: the manager stores every config with its own ACL (owner
# LocalSystem, inheritance off, Administrators get Delete only).
#
# This patch inserts the same Write-Conf helper and routes the final write
# through it.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-hop2conf-p44e.ps1 -Script C:\vpn\make-hop2-conf.ps1

param(
  [string]$Script = 'C:\vpn\make-hop2-conf.ps1',
  [string]$Insert = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$q = [char]34

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$Script = ('' + $Script).Trim().Trim($q)
$here = Split-Path -Parent $Script
if ($Insert -eq '') { $Insert = Join-Path $here 'p44e-writeconf.ps1.txt' }
$Insert = ('' + $Insert).Trim().Trim($q)
$backup = $Script + '.orig-p44e'

Say '==== AwgChain pack 44e: make-hop2-conf.ps1 ===='
Say ('file: ' + $Script)

if (-not (Test-Path -LiteralPath $Script)) {
  Bad 'make-hop2-conf.ps1 not found'
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
  Bad 'no pack 44e backup found'
  Say 'RESULT=FAIL reason=nobackup'
  exit 1
}

if (-not (Test-Path -LiteralPath $Insert)) {
  Bad ('the insert file is missing: ' + $Insert)
  Say 'RESULT=FAIL reason=noinsert'
  exit 1
}

$text = [System.IO.File]::ReadAllText($Script)

if ($text.Contains('function Write-Conf')) {
  Ok 'make-hop2-conf.ps1 already clears the old protected config'
  Say 'RESULT=OK'
  exit 0
}

$anchor = '[System.IO.File]::WriteAllText($Out, $text, $enc)'
if (-not $text.Contains($anchor)) {
  Bad 'the final write line was not found, the script differs from the known version'
  Say 'RESULT=FAIL reason=anchor'
  exit 1
}

$nl = "`r`n"
if (-not $text.Contains("`r`n")) { $nl = "`n" }

$helper = [System.IO.File]::ReadAllText($Insert)
$helper = $helper.Replace("`r`n", "`n").Replace("`n", $nl)

$call = 'Write-Conf -Path $Out -Text $text -Encoding $enc'
$text = $text.Replace($anchor, $helper + $nl + $call)

if (-not (Test-Path -LiteralPath $backup)) {
  Copy-Item -LiteralPath $Script -Destination $backup -Force
}

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Script, $text, $enc)

Ok 'make-hop2-conf.ps1 now clears the old protected config before writing'
Say 'RESULT=OK'
Say 'Next: awgchain.bat up'
exit 0
