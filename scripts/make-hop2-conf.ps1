# Builds the hop-2 config (Amnezia) so that it rides inside hop 1.
#
# Differences from make-hop1-conf.ps1:
#   - PinEndpointVia defaults to the hop-1 adapter, not the physical NIC
#   - routes ARE installed: hop 2 is the tunnel that carries app traffic,
#     so no Table = off here
#   - DNS is kept by default: it must resolve inside hop 2, not outside
#   - MTU is forced down, the profile value is for a direct connection and
#     is too large once everything is wrapped in hop 1
#
# Unchanged and important: every [Interface] key we do not handle is passed
# through verbatim. This profile carries Jc/Jmin/Jmax, S1-S4, H1-H4 as
# ranges like 110070076-488926149, and an I1 with an <r 2> repeat prefix.
# All of that must reach the server byte for byte.

param(
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][string]$Out,
  [string]$PinVia = 'hop1-warp',
  [int]$Mtu = 1340,
  [switch]$NoDns
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) {
  Write-Error "source config not found: $Source"
  exit 1
}

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

# IPv4 only. A live IPv6 default inside the chain is a path around hop 2.
$addr4 = @()
$addrRaw = Get-Val $iface 'Address'
if ($addrRaw) {
  foreach ($a in ($addrRaw -split ',')) {
    $a = $a.Trim()
    if ($a -ne '' -and $a -notmatch ':') { $addr4 += $a }
  }
}
if ($addr4.Count -eq 0) { Write-Error 'no IPv4 address in [Interface]'; exit 1 }

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

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('[Interface]')
$lines.Add("PrivateKey = $privKey")
$lines.Add("Address = $($addr4 -join ', ')")
$lines.Add("MTU = $Mtu")

$dnsUsed = 'dropped'
if (-not $NoDns) {
  $dnsRaw = Get-Val $iface 'DNS'
  if ($dnsRaw) {
    $dns4 = @()
    foreach ($d in ($dnsRaw -split ',')) {
      $d = $d.Trim()
      if ($d -ne '' -and $d -notmatch ':') { $dns4 += $d }
    }
    if ($dns4.Count -gt 0) {
      $lines.Add("DNS = $($dns4 -join ', ')")
      $dnsUsed = ($dns4 -join ', ')
    }
  }
}

# no Table = off here on purpose
$lines.Add("PinEndpointVia = $PinVia")
foreach ($x in $extra) { $lines.Add($x) }

$lines.Add('')
$lines.Add('[Peer]')
$lines.Add("PublicKey = $pubKey")
$psk = Get-Val $peer 'PresharedKey'
if ($psk) { $lines.Add("PresharedKey = $psk") }
# 0.0.0.0/0 is split in two: same coverage, but the built-in kill-switch
# only arms for a single peer with a literal /0 and would then block hop 1's
# own packets. ::/0 is dropped with the v6 address.
$lines.Add('AllowedIPs = 0.0.0.0/1, 128.0.0.0/1')
$lines.Add("Endpoint = $endpoint")
$lines.Add("PersistentKeepalive = $keepalive")

$text = ($lines -join "`r`n") + "`r`n"

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$enc = New-Object System.Text.UTF8Encoding($false)
function Write-Conf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Text,
    [Parameter(Mandatory=$true)]$Encoding
  )

  # The manager stores every config with its own hard ACL: owner LocalSystem,
  # inheritance disabled, Administrators get Delete only. Writing over such a
  # file fails with "Access to the path ... is denied" even from an elevated
  # console, while deleting it works. So: clear, delete, then write fresh.
  if (Test-Path -LiteralPath $Path) {
    $needsClear = $false
    try {
      $fs = [System.IO.File]::Open($Path, 'Open', 'Write', 'None')
      $fs.Close()
    } catch {
      $needsClear = $true
    }

    if ($needsClear) {
      try {
        $item = Get-Item -LiteralPath $Path -Force
        $item.Attributes = 'Normal'
      } catch {
        Write-Host 'could not clear the attributes, continuing anyway'
      }
      try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      } catch {
        & takeown.exe /f $Path /a | Out-Null
        & icacls.exe $Path /grant '*S-1-5-32-544:(F)' | Out-Null
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      }
      Write-Host "cleared the protected old config: $Path"
    }
  }

  [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

Write-Conf -Path $Out -Text $text -Encoding $enc

Write-Host "wrote $Out"
Write-Host "  address        : $($addr4 -join ', ')"
Write-Host "  endpoint       : $endpoint  (copied verbatim)"
Write-Host "  mtu            : $Mtu  (profile value overridden for the chain)"
if ($Mtu -lt 1280) {
  Write-Host '[WARN] below the 1280 byte IPv6 minimum. Without patch #3 Windows fails'
  Write-Host '       the v6 interface with "The parameter is incorrect" and the tunnel dies.'
}
Write-Host "  PinEndpointVia : $PinVia"
Write-Host "  dns            : $dnsUsed"
Write-Host '  routing        : routes INSTALLED, hop 2 carries all app traffic'
if ($passed.Count -gt 0) {
  Write-Host "  carried over   : $($passed -join ', ')"
} else {
  Write-Host '  carried over   : nothing - plain WireGuard profile'
}
if ($endpoint -notmatch '^\d{1,3}(\.\d{1,3}){3}:\d+$') {
  Write-Host '[WARN] endpoint is not a bare IPv4:port. A hostname is resolved BEFORE the'
  Write-Host '       socket is pinned, so that DNS query would leak outside the chain.'
}
exit 0
