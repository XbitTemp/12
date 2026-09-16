# Finds the largest ICMP payload that survives with DF set, then reports the
# path MTU and what that means for each hop of the chain.
#
# A WireGuard packet on IPv4 costs 60 bytes of overhead:
#   20 IP header + 8 UDP header + 32 WireGuard data header
# AmneziaWG adds nothing per packet in steady state - the junk packets and
# header magic are separate packets or replace existing header bytes.
#
# So:  tunnel MTU = path MTU - 60
# And for the inner hop: hop2 MTU = hop1 MTU - 60

param(
  [string]$Target = '1.1.1.1',
  [int]$Low = 1000,
  [int]$High = 1472,
  [string]$Label = 'path',
  # Set this when the probe runs from inside the chain. The script then reports
  # what it actually measured instead of subtracting the WireGuard overhead a
  # second time: inside the chain the measured path MTU already IS hop 2's MTU.
  [switch]$InChain
)

$ErrorActionPreference = 'Continue'

function Test-Payload([int]$size) {
  $out = & ping.exe -f -l $size -n 2 -w 2000 $Target 2>&1 | Out-String
  if ($out -match 'Reply from') { return $true }
  return $false
}

Write-Host "probing $Label to $Target, payload range $Low..$High"

if (-not (Test-Payload $Low)) {
  Write-Host "[WARN] even $Low bytes does not get through."
  Write-Host '       Either the target blocks ICMP or the link is down.'
  Write-Host 'MAXPAYLOAD=0'
  exit 2
}

$lo = $Low
$hi = $High
if (Test-Payload $hi) {
  $lo = $hi
} else {
  # classic binary search: lo always passes, hi always fails
  while (($hi - $lo) -gt 1) {
    $mid = [int](($lo + $hi) / 2)
    if (Test-Payload $mid) {
      $lo = $mid
      Write-Host ("  {0,5} ok" -f $mid)
    } else {
      $hi = $mid
      Write-Host ("  {0,5} too big" -f $mid)
    }
  }
}

$pathMtu = $lo + 28          # 20 IP + 8 ICMP header

Write-Host ''
Write-Host "max payload with DF : $lo bytes"
Write-Host "path MTU            : $pathMtu bytes"
Write-Host ''

if ($InChain) {
  $mtu2 = 0
  $ifc = Get-NetIPInterface -InterfaceAlias 'hop2-amnezia' -AddressFamily IPv4 -ErrorAction SilentlyContinue
  if ($ifc) { $mtu2 = [int]$ifc.NlMtu }
  Write-Host 'measured from inside the chain, so this IS hop 2:'
  Write-Host "  hop 2 usable MTU : $pathMtu"
  if ($mtu2 -gt 0) {
    Write-Host "  hop 2 configured : $mtu2"
    if ($pathMtu -eq $mtu2) {
      Write-Host '  verdict: honest - every configured byte actually arrives'
    } else {
      $gap = $mtu2 - $pathMtu
      Write-Host "  verdict: MTU BLACK HOLE - $gap bytes are dropped silently."
      Write-Host "           Lower hop 2 to $pathMtu and hop 1 to $($pathMtu + 60)."
    }
  }
  Write-Host ''
  Write-Host "MAXPAYLOAD=$lo"
  Write-Host "PATHMTU=$pathMtu"
  Write-Host "HOP2CONFIGURED=$mtu2"
  exit 0
}

$hop1 = $pathMtu - 60
$hop2 = $hop1 - 60
Write-Host 'derived chain settings:'
Write-Host "  hop 1 MTU : $hop1"
Write-Host "  hop 2 MTU : $hop2"
Write-Host '  warning: an ICMP probe to a WARP anycast address is answered by'
Write-Host '           the nearest Cloudflare edge, not by the WARP server, so'
Write-Host '           this number can be too optimistic. Confirm in the chain.'
if ($hop2 -lt 1280) {
  Write-Host '  note: hop 2 lands below the 1280 byte IPv6 minimum, so patch #3'
  Write-Host '        is what keeps it working. IPv6 inside the tunnel stays off.'
}
Write-Host ''
Write-Host "MAXPAYLOAD=$lo"
Write-Host "PATHMTU=$pathMtu"
Write-Host "HOP1MTU=$hop1"
Write-Host "HOP2MTU=$hop2"
exit 0
