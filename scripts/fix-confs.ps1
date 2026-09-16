# AwgChain - fix-confs.ps1
# Brings the source configs in C:\vpn in line with the measured values, so a
# file and the README never disagree again:
#
#   the WARP file  -> MTU 1420
#   the inner file -> MTU 1360, IPv6 resolvers dropped when it has no v6 address
#
# A copy of every changed file is kept as <name>.conf.orig-p38.
#
#   fix-confs.ps1 -Folder C:\vpn
#   fix-confs.ps1 -Folder C:\vpn -Revert

param(
  [string]$Folder = 'C:\vpn',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$fails = 0
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

$warpBlocks = @('162.159.', '188.114.', '8.6.11')

function Is-Warp([string]$text) {
  foreach ($b in $warpBlocks) { if ($text -match ('Endpoint\s*=\s*' + [regex]::Escape($b))) { return $true } }
  if ($text -match 'Endpoint\s*=\s*[^\r\n]*cloudflare') { return $true }
  return $false
}

function Has-V6Address([string]$text) {
  foreach ($line in ($text -split "`n")) {
    $l = $line.Trim()
    if ($l -match '^Address\s*=') {
      if ($l -match ':') { return $true }
    }
  }
  return $false
}

function Set-Mtu([string]$text, [int]$mtu) {
  if ($text -match '(?m)^\s*MTU\s*=.*$') {
    return [regex]::Replace($text, '(?m)^\s*MTU\s*=.*$', ('MTU = ' + $mtu))
  }
  return [regex]::Replace($text, '(?m)^(\[Peer\])', ("MTU = " + $mtu + "`r`n`r`n" + '$1'), 1)
}

function Strip-V6Dns([string]$text) {
  $out = @()
  foreach ($line in ($text -split "`r`n")) {
    if ($line.Trim() -match '^DNS\s*=') {
      $parts = ($line -split '=', 2)[1] -split ','
      $keep = @()
      foreach ($p in $parts) { $v = $p.Trim(); if ($v -ne '' -and $v -notmatch ':') { $keep = $keep + $v } }
      if ($keep.Count -gt 0) { $out = $out + ('DNS = ' + ($keep -join ', ')) }
      continue
    }
    $out = $out + $line
  }
  return ($out -join "`r`n")
}

$files = Get-ChildItem -LiteralPath $Folder -Filter '*.conf' -File -ErrorAction SilentlyContinue
if (-not $files) { Bad ('no .conf files in ' + $Folder); Write-Host 'RESULT=FAIL'; exit 1 }

foreach ($f in $files) {
  $bak = $f.FullName + '.orig-p38'
  if ($Revert) {
    if (Test-Path -LiteralPath $bak) {
      Copy-Item -LiteralPath $bak -Destination $f.FullName -Force
      Remove-Item -LiteralPath $bak -Force
      Ok ($f.Name + ' restored')
    }
    continue
  }
  $text = [System.IO.File]::ReadAllText($f.FullName)
  if ($text -match 'PinEndpointVia') { Write-Host ('  ' + $f.Name + ' is a built hop config, skipping'); continue }
  $isWarp = Is-Warp $text
  $new = $text
  if ($isWarp) {
    $new = Set-Mtu $new 1420
  } else {
    $new = Set-Mtu $new 1360
    if (-not (Has-V6Address $new)) { $new = Strip-V6Dns $new }
  }
  if ($new -eq $text) { Write-Host ('  ' + $f.Name + ' already correct'); continue }
  if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $f.FullName -Destination $bak -Force }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($f.FullName, $new, $enc)
  if ($isWarp) { Ok ($f.Name + ' -> WARP hop, MTU 1420') } else { Ok ($f.Name + ' -> inner hop, MTU 1360, v6 resolvers cleaned') }
}

if ($fails -gt 0) { Write-Host 'RESULT=FAIL'; exit 1 }
Write-Host 'RESULT=OK'
exit 0
