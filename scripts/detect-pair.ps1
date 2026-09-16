param(
	[string]$Data = 'C:\Program Files\AwgChain\Data\Configurations',
	[switch]$Explain
)

$ErrorActionPreference = 'SilentlyContinue'

function Clean-Name($n) {
	if (-not $n) { return '' }
	$n = $n -replace '^AwgChainTunnel\$', ''
	$n = $n -replace '\.dpapi$', ''
	$n = $n -replace '\.conf$', ''
	$n = $n -replace '-hop1$', ''
	return $n.Trim()
}

function Name-Ok($n) {
	if (-not $n) { return $false }
	if ($n -match '[\\/:*?"<>|\s]') { return $false }
	return $true
}

$pair = ''
$src = ''

# 1. a running or installed hidden hop service: AwgChainTunnel$<pair>-hop1
$svc = Get-Service | Where-Object { $_.Name -like 'AwgChainTunnel$*-hop1' } | Select-Object -First 1
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

# 3. a stored config named <pair>-hop1.conf or <pair>-hop1.conf.dpapi
if (-not (Name-Ok $pair)) {
	$f = Get-ChildItem -LiteralPath $Data -File |
		Where-Object { $_.Name -like '*-hop1.conf' -or $_.Name -like '*-hop1.conf.dpapi' } |
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

if (-not (Name-Ok $pair)) {
	if ($Explain) { Write-Host 'source: nothing found' }
	exit 0
}

if ($Explain) {
	Write-Host ('source: ' + $src)
	Write-Host ('pair  : ' + $pair)
	Write-Host ('hop1  : ' + $pair + '-hop1')
	exit 0
}

Write-Output $pair
