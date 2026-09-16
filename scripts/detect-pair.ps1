# AwgChain pack 44d: detect-pair.ps1 v2.
#
# v1 could hand the bat a name it never checked, and after the protected
# warpam-hop1.conf was deleted that is exactly what happened: the pair became
# " =", the bat created " =-hop1.conf" / " =.conf" and the adapter never came up.
#
# v2 rules:
#   - a name is accepted only if it matches ^[A-Za-z0-9_][A-Za-z0-9_-]{0,47}$
#   - if nothing valid is found, the default name is printed ($Default,
#     "warpam"), so the chain always has a sane pair to work with
#   - only the name goes to stdout, nothing else, because the bat captures it
#   - -Explain prints the reasoning for humans
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\detect-pair.ps1 -Explain

param(
  [string]$Data = 'C:\Program Files\AwgChain\Data\Configurations',
  [string]$Default = 'warpam',
  [switch]$Explain
)

$ErrorActionPreference = 'SilentlyContinue'

$good = '^[A-Za-z0-9_][A-Za-z0-9_-]{0,47}$'

function Clean-Name($n) {
  if (-not $n) { return '' }
  $n = $n -replace '^AwgChainTunnel\$', ''
  $n = $n -replace '\.dpapi$', ''
  $n = $n -replace '\.conf$', ''
  $n = $n -replace '-hop1$', ''
  return ('' + $n).Trim()
}

function Name-Ok($n) {
  if (-not $n) { return $false }
  if ($n -notmatch $good) { return $false }
  return $true
}

$pair = ''
$src = ''

# 1. an installed hidden hop service: AwgChainTunnel$<name>-hop1
$svc = Get-Service | Where-Object { $_.Name -like 'AwgChainTunnel$*-hop1' } |
  Where-Object { (Clean-Name $_.Name) -match $good } |
  Select-Object -First 1
if ($svc) {
  $pair = Clean-Name $svc.Name
  $src = 'service ' + $svc.Name
}

# 2. the old console pair from before patch 14
if (-not (Name-Ok $pair)) {
  $svc = Get-Service | Where-Object { $_.Name -eq 'AwgChainTunnel$hop1-warp' } | Select-Object -First 1
  if ($svc) {
    $pair = 'hop2-amnezia'
    $src = 'legacy service ' + $svc.Name
  }
}

# 3. a stored config named <name>-hop1.conf or <name>-hop1.conf.dpapi
if (-not (Name-Ok $pair)) {
  $f = Get-ChildItem -LiteralPath $Data -File |
    Where-Object { $_.Name -like '*-hop1.conf' -or $_.Name -like '*-hop1.conf.dpapi' } |
    Where-Object { (Clean-Name $_.Name) -match $good } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($f) {
    $pair = Clean-Name $f.Name
    $src = 'config ' + $f.Name
  }
}

# 4. the old console config names
if (-not (Name-Ok $pair)) {
  $f = Get-ChildItem -LiteralPath $Data -File |
    Where-Object { $_.Name -like 'hop1-warp.conf*' } | Select-Object -First 1
  if ($f) {
    $pair = 'hop2-amnezia'
    $src = 'legacy config ' + $f.Name
  }
}

# 5. nothing valid on this machine yet - use the default name
if (-not (Name-Ok $pair)) {
  $pair = ('' + $Default).Trim()
  $src = 'the built-in default name'
}

# last line of defence: never hand the bat something it cannot use
if (-not (Name-Ok $pair)) {
  $pair = 'warpam'
  $src = 'hard fallback'
}

if ($Explain) {
  Write-Host ('source: ' + $src)
  Write-Host ('pair  : ' + $pair)
  Write-Host ('hop1  : ' + $pair + '-hop1')
  exit 0
}

Write-Output $pair
