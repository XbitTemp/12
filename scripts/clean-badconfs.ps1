# AwgChain pack 44c: sweep the junk configs the broken pair name created.
#
# The failed "up" wrote " =-hop1.conf" and " =.conf" into the stored
# configurations folder, and also left services / adapters with that name.
# This removes all of it: services first, then the files (taking ownership
# when the upstream ACL blocks us).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\clean-badconfs.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\clean-badconfs.ps1 -Apply

param(
  [string]$Data = 'C:\Program Files\AwgChain\Data\Configurations',
  [switch]$Apply
)

$ErrorActionPreference = 'Continue'

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

Say '==== AwgChain pack 44c: junk configs and services ===='
Say ('folder: ' + $Data)

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Bad 'this console is NOT elevated'
  Say 'RESULT=FAIL reason=notelevated'
  exit 1
}

$good = '^[A-Za-z0-9_][A-Za-z0-9_-]*$'

$svcs = @()
Get-Service -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'AwgChainTunnel$*' } |
  ForEach-Object {
    $base = $_.Name -replace '^AwgChainTunnel\$', ''
    if ($base -notmatch $good) { $svcs += $_.Name }
  }

$files = @()
if (Test-Path -LiteralPath $Data) {
  Get-ChildItem -LiteralPath $Data -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
      $base = $_.Name -replace '\.dpapi$', ''
      $base = $base -replace '\.conf$', ''
      $base = $base -replace '-hop1$', ''
      if ($base -notmatch $good) { $files += $_.FullName }
    }
}

Say ''
Say 'services with a bad name:'
if ($svcs.Count -eq 0) { Say '  none' } else { foreach ($s in $svcs) { Say ('  ' + $s) } }
Say 'files with a bad name:'
if ($files.Count -eq 0) { Say '  none' } else { foreach ($f in $files) { Say ('  ' + $f) } }

if ($svcs.Count -eq 0 -and $files.Count -eq 0) {
  Say ''
  Ok 'nothing to clean'
  Say 'RESULT=OK'
  exit 0
}

if (-not $Apply) {
  Say ''
  Say 'Run the same command with -Apply to remove everything listed above.'
  Say 'RESULT=NEEDSAPPLY'
  exit 0
}

foreach ($s in $svcs) {
  Say ('stopping and deleting ' + $s)
  & "$env:SystemRoot\System32\sc.exe" stop $s | Out-Null
  Start-Sleep -Seconds 2
  & "$env:SystemRoot\System32\sc.exe" delete $s | Out-Null
}

foreach ($f in $files) {
  Say ('removing ' + $f)
  try { (Get-Item -LiteralPath $f -Force).Attributes = 'Normal' } catch { }
  Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $f) {
    & "$env:SystemRoot\System32\takeown.exe" /f $f /a | Out-Null
    & "$env:SystemRoot\System32\icacls.exe" $f /grant '*S-1-5-32-544:(F)' | Out-Null
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $f) { Bad ('could not remove ' + $f) }
}

Say ''
Ok 'cleanup done, now run: awgchain.bat up'
Say 'RESULT=OK'
exit 0
