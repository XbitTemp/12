# Builds the hop-1 config from a WARP / AmneziaWG profile.
#
# v4. In the chain this is called WITHOUT -Routed, so it writes Table = off:
# hop 1 installs no routes at all, hop 2 owns the routing table. -Routed
# exists only for testing hop 1 on its own.
#
# Rules:
#  - every [Interface] key we do not handle ourselves is passed through
#    untouched. That keeps Jc/Jmin/Jmax/H1..H4/I1..I5/S1..S4 alive - they
#    must match the server byte for byte.
#  - Endpoint is copied verbatim, host AND port. Hardcoding 2408 breaks it.
#  - IPv6 addresses and ::/0 are dropped: a live v6 default is a path
#    around hop 2.
#  - DNS is dropped, it belongs to hop 2. -KeepDns overrides.
#  - AllowedIPs becomes 0.0.0.0/1 + 128.0.0.0/1: same coverage as /0 but it
#    does not arm the built-in kill-switch, which would block hop 1 itself.
#  - PinEndpointVia is added, that is our patch #1.

param(
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][string]$Out,
  [string]$PinVia = '',
  [int]$Mtu = 0,
  [switch]$KeepDns,
  [switch]$Routed
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) {
  Write-Error "source config not found: $Source"
  exit 1
}

# ---------- pick the interface that currently owns the default route ----------
if ([string]::IsNullOrWhiteSpace($PinVia)) {
  try {
    $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
         Sort-Object -Property RouteMetric,ifMetric |
         Select-Object -First 1
    if ($r) {
      $ad = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction Stop
      $PinVia = $ad.Name
      Write-Host "default route currently on: $PinVia (ifIndex $($r.ifIndex))"
    }
  } catch {
    Write-Host "[WARN] could not detect the default interface: $($_.Exception.Message)"
  }
}
if ([string]::IsNullOrWhiteSpace($PinVia)) {
  Write-Error 'could not determine PinEndpointVia, pass it with -PinVia "Ethernet"'
  exit 1
}

# ---------- parse ----------
$section = ''
$iface   = New-Object System.Collections.Generic.List[object]
$peer    = New-Object System.Collections.Generic.List[object]

foreach ($raw in (Get-Content -LiteralPath $Source)) {
  $line = $raw.Trim()
  if ($line -eq '') { continue }
  if ($line.StartsWith('#') -or $line.StartsWith(';')) { continue }
  if ($line -match '^\[(.+)\]$') { $section = $Matches[1].Trim().ToLower(); continue }
  $idx = $line.IndexOf('=')
  if ($idx -lt 1) { continue }
  $k = $line.Substring(0, $idx).Trim()
  $v = $line.Substring($idx + 1).Trim()
  $kv = [pscustomobject]@{ Key = $k; Value = $v }
  if     ($section -eq 'interface') { $iface.Add($kv) }
  elseif ($section -eq 'peer')      { $peer.Add($kv) }
}

function Get-Val {
  param($list, [string]$name)
  foreach ($e in $list) { if ($e.Key -ieq $name) { return $e.Value } }
  return $null
}

$privKey  = Get-Val $iface 'PrivateKey'
$pubKey   = Get-Val $peer  'PublicKey'
$endpoint = Get-Val $peer  'Endpoint'
if (-not $privKey)  { Write-Error 'no PrivateKey in [Interface]'; exit 1 }
if (-not $pubKey)   { Write-Error 'no PublicKey in [Peer]';      exit 1 }
if (-not $endpoint) { Write-Error 'no Endpoint in [Peer]';        exit 1 }

$addr4 = @()
$addrRaw = Get-Val $iface 'Address'
if ($addrRaw) {
  foreach ($a in ($addrRaw -split ',')) {
    $a = $a.Trim()
    if ($a -ne '' -and $a -notmatch ':') { $addr4 += $a }
  }
}
if ($addr4.Count -eq 0) { Write-Error 'no IPv4 address in [Interface]'; exit 1 }

# The chain raises hop 1's MTU above the profile default. Everything hop 2
# sends is wrapped again here, so a roomy outer tunnel is what lets the inner
# one stay at or above the 1280 byte IPv6 minimum.
if ($Mtu -gt 0) {
  $mtu = "$Mtu"
} else {
  $mtu = Get-Val $iface 'MTU'
  if (-not $mtu) { $mtu = '1280' }
}

$keepalive = Get-Val $peer 'PersistentKeepalive'
if (-not $keepalive) { $keepalive = '25' }

$handled = @('PrivateKey','Address','MTU','DNS','ListenPort','Table','PinEndpointVia')
$passed  = @()
$extra   = @()
foreach ($e in $iface) {
  if ($handled -contains $e.Key) { continue }
  $extra  += "$($e.Key) = $($e.Value)"
  $passed += $e.Key
}

# ---------- build ----------
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('[Interface]')
$lines.Add("PrivateKey = $privKey")
$lines.Add("Address = $($addr4 -join ', ')")
$lines.Add("MTU = $mtu")

if ($KeepDns) {
  $dnsRaw = Get-Val $iface 'DNS'
  if ($dnsRaw) {
    $dns4 = @()
    foreach ($d in ($dnsRaw -split ',')) {
      $d = $d.Trim()
      if ($d -ne '' -and $d -notmatch ':') { $dns4 += $d }
    }
    if ($dns4.Count -gt 0) { $lines.Add("DNS = $($dns4 -join ', ')") }
  }
}

if (-not $Routed) { $lines.Add('Table = off') }
$lines.Add("PinEndpointVia = $PinVia")
foreach ($x in $extra) { $lines.Add($x) }

$lines.Add('')
$lines.Add('[Peer]')
$lines.Add("PublicKey = $pubKey")
$psk = Get-Val $peer 'PresharedKey'
if ($psk) { $lines.Add("PresharedKey = $psk") }
$lines.Add('AllowedIPs = 0.0.0.0/1, 128.0.0.0/1')
$lines.Add("Endpoint = $endpoint")
$lines.Add("PersistentKeepalive = $keepalive")

$text = ($lines -join "`r`n") + "`r`n"

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$enc = New-Object System.Text.UTF8Encoding($false)
function Write-Conf {
  param([string]$Path, [string]$Text, $Encoding)

  if (Test-Path -LiteralPath $Path) {
    $fixed = @()
    try {
      $fi = Get-Item -LiteralPath $Path -Force
      if ($fi.Attributes -ne 'Normal') {
        try { $fi.Attributes = 'Normal'; $fixed += 'attributes' } catch { }
      }
    } catch { }

    $writable = $false
    try {
      $fs = [System.IO.File]::Open($Path, 'Open', 'Write', 'None')
      $fs.Close()
      $writable = $true
    } catch { }

    if (-not $writable) {
      & "$env:SystemRoot\System32\takeown.exe" /f $Path /a | Out-Null
      & "$env:SystemRoot\System32\icacls.exe" $Path /grant '*S-1-5-32-544:(F)' | Out-Null
      $fixed += 'owner and access list'
    }

    try {
      Remove-Item -LiteralPath $Path -Force
      $fixed += 'removed the old file'
    } catch {
      Write-Host ('[WARN] could not remove the old config: ' + $_.Exception.Message)
    }

    if ($fixed.Count -gt 0) {
      Write-Host ('cleared the protected old config: ' + ($fixed -join ', '))
    }
  }

  [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

Write-Conf -Path $Out -Text $text -Encoding $enc

# ---------- report ----------
Write-Host "wrote $Out"
Write-Host "  address        : $($addr4 -join ', ')"
Write-Host "  endpoint       : $endpoint  (copied verbatim)"
Write-Host "  mtu            : $mtu"
Write-Host "  PinEndpointVia : $PinVia"
if ($Routed) {
  Write-Host '  routing        : routes INSTALLED, hop 1 carries traffic, egress must change'
} else {
  Write-Host '  routing        : Table = off, no routes - correct for the chain'
}
if ($passed.Count -gt 0) {
  Write-Host "  carried over   : $($passed -join ', ')"
} else {
  Write-Host '  carried over   : nothing - plain WireGuard profile, no obfuscation keys'
}
if ($endpoint -notmatch '^\d{1,3}(\.\d{1,3}){3}:\d+$') {
  Write-Host '[WARN] the endpoint is not a bare IPv4:port. A hostname is resolved before the'
  Write-Host '       socket is pinned, which leaks that DNS query outside the chain.'
}
exit 0
