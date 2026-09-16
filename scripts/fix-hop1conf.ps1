# AwgChain pack 44b: the hop 1 config FILE, not the folder.
#
# fix-confdir.ps1 proved the folder is fine: elevated True, writable True,
# Administrators own it. The denial happens on the file itself:
#   Access to the path '...\Configurations\warpam-hop1.conf' is denied.
# The upstream client stores every config with its own tight ACL (LocalSystem
# only, inheritance off) and can also mark it read only or hidden. Our script
# opens that existing file for writing, so it is refused even for an admin.
#
# This script shows exactly what is on that file and, with -Apply, clears the
# attributes, takes ownership, grants Administrators full control and deletes
# the file so the next "awgchain.bat up" writes a fresh one.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\fix-hop1conf.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\fix-hop1conf.ps1 -Apply

param(
  [string]$File = 'C:\Program Files\AwgChain\Data\Configurations\warpam-hop1.conf',
  [switch]$Apply
)

$ErrorActionPreference = 'Continue'

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

Say '==== AwgChain pack 44b: hop 1 config file ===='
Say ('file: ' + $File)

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Bad 'this console is NOT elevated, open cmd with "Run as administrator"'
  Say 'RESULT=FAIL reason=notelevated'
  exit 1
}

if (-not (Test-Path -LiteralPath $File)) {
  Ok 'the file does not exist, so nothing blocks writing it'
  Say 'RESULT=OK reason=nofile'
  exit 0
}

$fi = Get-Item -LiteralPath $File -Force
Say ('size       : ' + $fi.Length + ' bytes')
Say ('written    : ' + $fi.LastWriteTime)
Say ('attributes : ' + $fi.Attributes)

Say ''
Say 'access list on the file:'
$acl = Get-Acl -LiteralPath $File
Say ('owner: ' + $acl.Owner)
Say ('inheritance blocked: ' + $acl.AreAccessRulesProtected)
foreach ($a in $acl.Access) {
  Say ('  ' + $a.IdentityReference.Value + ' : ' + $a.FileSystemRights + ' (' + $a.AccessControlType + ')')
}

$canWrite = $false
try {
  $fs = [System.IO.File]::Open($File, 'Open', 'Write', 'None')
  $fs.Close()
  $canWrite = $true
} catch {
  Say ''
  Say ('write test failed: ' + $_.Exception.Message)
}
Say ('writable now : ' + $canWrite)

if ($canWrite) {
  Say ''
  Ok 'the file is writable from this console, run: awgchain.bat up'
  Say 'RESULT=OK'
  exit 0
}

if (-not $Apply) {
  Say ''
  Say 'Run the same command with -Apply: it clears the attributes, takes'
  Say 'ownership, grants Administrators full control and deletes the file.'
  Say 'The config is rebuilt from C:\vpn\WARPv2_84.conf on the next "up".'
  Say 'RESULT=NEEDSAPPLY'
  exit 0
}

Say ''
Say 'clearing attributes...'
try { $fi.Attributes = 'Normal' } catch { Say ('  ' + $_.Exception.Message) }
Say 'taking ownership...'
& "$env:SystemRoot\System32\takeown.exe" /f $File /a | Out-Null
Say 'granting the Administrators group full control...'
& "$env:SystemRoot\System32\icacls.exe" $File /grant '*S-1-5-32-544:(F)' | Out-Null
Say 'deleting the stale config...'
Remove-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $File) {
  Bad 'the file is still there, send me this whole output'
  Say 'RESULT=FAIL reason=stillthere'
  exit 1
}
Ok 'the stale config is gone, now run: awgchain.bat up'
Say 'RESULT=OK'
exit 0
