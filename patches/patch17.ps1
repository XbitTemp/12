# AwgChain patch 17 - the editor gets the WARP half from the manager
#
#   1. ui\chainbuild.go   new version: the hidden hop is read over IPC
#
# Patch 15 has to be applied first. The replaced file is backed up once
# as chainbuild.go.orig-p17. Undo with -Revert. Re-running is safe.

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Core = 'C:\dev\vpnchain\amneziawg-windows',
  [string]$Here = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

$Here = ('' + $Here).Trim().Trim('"').Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Client = ('' + $Client).Trim().Trim('"').Trim().TrimEnd('\')
$Core = ('' + $Core).Trim().Trim('"').Trim().TrimEnd('\')

$fails = 0

function Say([string]$m) { Write-Host $m }
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Write-Text([string]$path, [string]$text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Backup-Once([string]$path) {
  $b = $path + '.orig-p17'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p17'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Write-Host ('[OK] ' + $label + ' was restored from the backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

function Insert-Before([string]$text, [string]$pattern, [string]$insert) {
  $rx = New-Object System.Text.RegularExpressions.Regex($pattern)
  $m = $rx.Match($text)
  if (-not $m.Success) { return $null }
  $nl = "`n"
  if ($text.Contains("`r`n")) { $nl = "`r`n" }
  $indent = $m.Groups[1].Value
  $body = ''
  foreach ($line in ($insert -split "`n")) {
    $l = $line.TrimEnd("`r")
    if ($l -eq '') { $body = $body + $nl }
    else { $body = $body + $indent + $l + $nl }
  }
  return $text.Substring(0, $m.Index) + $body + $text.Substring($m.Index)
}

function Replace-Once([string]$text, [string]$old, [string]$new) {
  $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
  if ($count -ne 1) { return $null }
  return $text.Replace($old, $new)
}
Say ''
Say '=== AwgChain patch 17: the WARP half is read through the manager ==='
Say ('client: ' + $Client)
Say ('here:   ' + $Here)
Say ''

$uiSrc = Join-Path $Here 'chainbuild-ui.go'
$uiDst = Join-Path $Client 'ui\chainbuild.go'
$editGo = Join-Path $Client 'ui\editdialog.go'

if (-not (Test-Path -LiteralPath $editGo)) {
  Bad ('the source file was not found: ' + $editGo)
  Say 'RESULT=FAIL'
  exit 1
}

if ($Revert) {
  Say '--- revert ---'
  Restore-Backup $uiDst 'ui\chainbuild.go'
  Say ''
  Say 'RESULT=REVERTED'
  Say 'Rebuild the client with: awgchain.bat build'
  exit 0
}

$editText = Get-Content -LiteralPath $editGo -Raw
if (-not $editText.Contains('chainEditorText')) {
  Bad 'editdialog.go carries no patch 15 hook, so run awgchain.bat patch15 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

Say '--- 1. ui\chainbuild.go: load the hidden hop over the manager pipe ---'
if (-not (Test-Path -LiteralPath $uiSrc)) {
  Bad ('chainbuild-ui.go was not found next to this script: ' + $uiSrc)
} else {
  if (Test-Path -LiteralPath $uiDst) { Backup-Once $uiDst }
  Copy-Item -LiteralPath $uiSrc -Destination $uiDst -Force
  $now = Get-Content -LiteralPath $uiDst -Raw
  if ($now.Contains('chainStoredHopConfig')) {
    Ok 'ui\chainbuild.go now asks the manager for the WARP half'
  } else {
    Bad 'the copied ui\chainbuild.go has no chainStoredHopConfig, so the pack is incomplete'
  }
}

Say ''
if ($fails -eq 0) {
  Say 'RESULT=OK'
  exit 0
}
Say ('RESULT=FAIL failed steps: ' + $fails)
exit 1
