# AwgChain pack 44a: why "awgchain.bat up" says
#   Access to the path 'C:\Program Files\AwgChain\Data\Configurations\warpam-hop1.conf' is denied.
#
# The upstream client protects its Configurations folder on purpose: only
# LocalSystem is allowed inside, because stored configs hold private keys.
# make-hop1-conf.ps1 writes the hop 1 config from your console, so it needs
# write access there.
#
# This script tells you exactly what is wrong, and with -Apply it takes
# ownership of that folder and grants the local Administrators group full
# control. Nothing else is touched.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\fix-confdir.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\fix-confdir.ps1 -Apply

param(
  [string]$Dir = 'C:\Program Files\AwgChain\Data\Configurations',
  [switch]$Apply
)

$ErrorActionPreference = 'Continue'

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

Say '==== AwgChain pack 44a: configurations folder ===='
Say ('folder: ' + $Dir)

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say ('running as    : ' + $id.Name)
Say ('elevated      : ' + $elevated)
if (-not $elevated) {
  Bad 'this console is NOT elevated. Close it and open cmd with "Run as administrator".'
  Say 'RESULT=FAIL reason=notelevated'
  exit 1
}

if (-not (Test-Path -LiteralPath $Dir)) {
  Bad 'the folder does not exist, is AwgChain installed?'
  Say 'RESULT=FAIL reason=nodir'
  exit 1
}

$probe = Join-Path $Dir 'awgchain-write-probe.tmp'
$canWrite = $false
try {
  [System.IO.File]::WriteAllText($probe, 'probe')
  Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  $canWrite = $true
} catch {
  Say ('write probe failed: ' + $_.Exception.Message)
}
Say ('writable now  : ' + $canWrite)

Say ''
Say 'current access list:'
$acl = Get-Acl -LiteralPath $Dir
Say ('owner: ' + $acl.Owner)
foreach ($a in $acl.Access) {
  Say ('  ' + $a.IdentityReference.Value + ' : ' + $a.FileSystemRights + ' (' + $a.AccessControlType + ')')
}

if ($canWrite) {
  Say ''
  Ok 'the folder is already writable from this console, nothing to do'
  Say 'RESULT=OK'
  exit 0
}

if (-not $Apply) {
  Say ''
  Say 'Run the same command with -Apply to take ownership and grant the local'
  Say 'Administrators group full control of this folder.'
  Say 'Note: these configs hold private keys, so only do this on the test machine.'
  Say 'RESULT=NEEDSAPPLY'
  exit 0
}

Say ''
Say 'taking ownership...'
& "$env:SystemRoot\System32\takeown.exe" /f $Dir /a /r /d Y | Out-Null
Say 'granting the Administrators group full control...'
& "$env:SystemRoot\System32\icacls.exe" $Dir /grant '*S-1-5-32-544:(OI)(CI)F' /t | Out-Null

$canWrite2 = $false
try {
  [System.IO.File]::WriteAllText($probe, 'probe')
  Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  $canWrite2 = $true
} catch {
  Say ('write probe still failing: ' + $_.Exception.Message)
}

if ($canWrite2) {
  Ok 'the folder is writable now, run: awgchain.bat up'
  Say 'RESULT=OK'
  exit 0
}
Bad 'still not writable, send me this whole output'
Say 'RESULT=FAIL reason=acl'
exit 1
