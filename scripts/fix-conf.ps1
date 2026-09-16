# AwgChain pack 44e: diagnose and clear ANY protected stored config.
#
# This is the pack 44b fix-hop1conf.ps1 made generic: it works on hop 1, hop 2
# or any other name, because the manager protects every stored config the same
# way (owner LocalSystem, inheritance off, Administrators get Delete only).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\fix-conf.ps1 -Name warpam
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\fix-conf.ps1 -Name warpam -Apply
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\fix-conf.ps1 -All -Apply

param(
  [string]$Name = 'warpam',
  [switch]$All,
  [string]$Data = 'C:\Program Files\AwgChain\Data\Configurations',
  [switch]$Apply
)

$ErrorActionPreference = 'Continue'

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

Say '==== AwgChain pack 44e: stored config files ===='
Say ('folder: ' + $Data)

if (-not (Test-Path -LiteralPath $Data)) {
  Bad 'the configurations folder does not exist'
  Say 'RESULT=FAIL reason=nofolder'
  exit 1
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say ('elevated: ' + $elevated)
if (-not $elevated) {
  Bad 'run this from an elevated console'
  Say 'RESULT=FAIL reason=notelevated'
  exit 1
}

$targets = @()
if ($All) {
  $targets = Get-ChildItem -LiteralPath $Data -File |
    Where-Object { $_.Name -like '*.conf' -or $_.Name -like '*.conf.dpapi' } |
    ForEach-Object { $_.FullName }
} else {
  $n = ('' + $Name).Trim()
  $targets = @(
    (Join-Path $Data ($n + '.conf')),
    (Join-Path $Data ($n + '.conf.dpapi')),
    (Join-Path $Data ($n + '-hop1.conf')),
    (Join-Path $Data ($n + '-hop1.conf.dpapi'))
  )
}

$stuck = @()

foreach ($p in $targets) {
  if (-not (Test-Path -LiteralPath $p)) { continue }
  Say ''
  Say ('file: ' + $p)
  $item = Get-Item -LiteralPath $p -Force
  Say ('size       : ' + $item.Length + ' bytes')
  Say ('written    : ' + $item.LastWriteTime)
  Say ('attributes : ' + $item.Attributes)
  try {
    $acl = Get-Acl -LiteralPath $p
    Say ('owner: ' + $acl.Owner)
    Say ('inheritance blocked: ' + $acl.AreAccessRulesProtected)
    foreach ($r in $acl.Access) {
      Say ('  ' + $r.IdentityReference.Value + ' : ' + $r.FileSystemRights + ' (' + $r.AccessControlType + ')')
    }
  } catch {
    Say 'could not read the access list'
  }

  $writable = $false
  try {
    $fs = [System.IO.File]::Open($p, 'Open', 'Write', 'None')
    $fs.Close()
    $writable = $true
  } catch {
    Say ('write test failed: ' + $_.Exception.Message)
  }
  Say ('writable now : ' + $writable)
  if (-not $writable) { $stuck += $p }
}

if ($stuck.Count -eq 0) {
  Say ''
  Ok 'no protected config is in the way, nothing to do'
  Say 'RESULT=OK'
  exit 0
}

if (-not $Apply) {
  Say ''
  Say 'These files cannot be overwritten:'
  foreach ($p in $stuck) { Say ('  ' + $p) }
  Say 'Run the same command with -Apply to delete them. The chain rebuilds'
  Say 'both configs from C:\vpn on the next "up".'
  Say 'RESULT=NEEDSAPPLY'
  exit 0
}

$failed = 0
foreach ($p in $stuck) {
  Say ''
  Say ('clearing ' + $p)
  try {
    $item = Get-Item -LiteralPath $p -Force
    $item.Attributes = 'Normal'
  } catch {
    Say 'attributes could not be cleared, continuing'
  }
  try {
    Remove-Item -LiteralPath $p -Force -ErrorAction Stop
  } catch {
    Say 'taking ownership and granting the Administrators group full control'
    & takeown.exe /f $p /a | Out-Null
    & icacls.exe $p /grant '*S-1-5-32-544:(F)' | Out-Null
    try {
      Remove-Item -LiteralPath $p -Force -ErrorAction Stop
    } catch {
      Bad ('could not delete ' + $p)
      $failed = $failed + 1
      continue
    }
  }
  Ok ('gone: ' + $p)
}

if ($failed -gt 0) {
  Say 'RESULT=FAIL reason=delete'
  exit 1
}

Say ''
Ok 'the stale configs are gone, now run: awgchain.bat up'
Say 'RESULT=OK'
exit 0
