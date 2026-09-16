# AwgChain patch 18 - IPv6 does not walk around the chain any more.
#
#   1. conf\chainipv6.go   new file: v6 halves, v6 detection, DNS filter
#   2. conf\chainbuild.go  the inner hop takes ::/1 + 8000::/1 when it can,
#                          and v6 resolvers are dropped when it cannot
#
# Backup: chainbuild.go.orig-p18. Undo with -Revert. Re-running is safe.

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
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Write-Go([string]$path, [string]$text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  $text = $text -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Backup-Once([string]$path) {
  $b = $path + '.orig-p18'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  original kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p18'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Ok ($label + ' restored from backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

$confDir = Join-Path $Core 'conf'
$buildGo = Join-Path $confDir 'chainbuild.go'
$ipv6Go = Join-Path $confDir 'chainipv6.go'

Write-Host '=== AwgChain patch 18: IPv6 inside the chain ==='
Write-Host ('core    : ' + $Core)

if (-not (Test-Path -LiteralPath $confDir)) { Bad ('no conf folder: ' + $confDir); Write-Host 'RESULT=FAIL'; exit 1 }
if (-not (Test-Path -LiteralPath $buildGo)) { Bad ('patch 14 is not applied, no ' + $buildGo); Write-Host 'RESULT=FAIL'; exit 1 }

if ($Revert) {
  Restore-Backup $buildGo 'conf\chainbuild.go'
  if (Test-Path -LiteralPath $ipv6Go) { Remove-Item -LiteralPath $ipv6Go -Force; Ok 'conf\chainipv6.go removed' }
  if ($fails -gt 0) { Write-Host 'RESULT=FAIL'; exit 1 }
  Write-Host 'RESULT=OK'
  Write-Host 'Now rebuild and install:  awgchain.bat build   then   awgchain.bat install'
  exit 0
}

$goSrc = @'
//go:build windows

/* AwgChain - patch 18: IPv6 does not walk around the chain.
 *
 * Until now the inner hop only claimed 0.0.0.0/1 + 128.0.0.0/1, so every
 * IPv6 packet kept using the physical adapter: the provider saw it, and a
 * web page could read the real address over v6 while v4 went through the
 * chain. The kill switch blocked v6 at the firewall, but only while it was
 * armed, and blocking is not routing.
 *
 * Two honest outcomes, decided by the inner hop itself:
 *
 *   the inner hop has an IPv6 address  -> it also claims ::/1 + 8000::/1,
 *                                         v6 rides the chain like v4
 *   the inner hop has no IPv6 address  -> v6 resolvers are dropped from the
 *                                         config and ipv6-lock.ps1 unbinds
 *                                         v6 from the physical adapter
 *
 * Never leave the third state: v6 up on the physical adapter while v4 is in
 * the chain.
 */

package conf

import "net"

// ChainConfigHasIPv6 reports whether this hop can carry IPv6 at all, which is
// true exactly when its Interface section holds a v6 address.
func ChainConfigHasIPv6(c *Config) bool {
	if c == nil {
		return false
	}
	for _, addr := range c.Interface.Addresses {
		if addr.IP != nil && addr.IP.To4() == nil {
			return true
		}
	}
	return false
}

// chainSplitDefaultV6 is the v6 twin of chainSplitDefault: a pair of halves
// beats any ::/0 that another adapter may hold.
func chainSplitDefaultV6() []IPCidr {
	return []IPCidr{
		{IP: net.ParseIP("::"), Cidr: 1},
		{IP: net.ParseIP("8000::"), Cidr: 1},
	}
}

// chainSplitDefaultFor returns the AllowedIPs of the inner hop: both v4
// halves always, both v6 halves when the hop has a v6 address of its own.
func chainSplitDefaultFor(hop *Config) []IPCidr {
	out := chainSplitDefault()
	if ChainConfigHasIPv6(hop) {
		out = append(out, chainSplitDefaultV6()...)
	}
	return out
}

// chainFilterDNS keeps v6 resolvers only when the chain can reach them.
// A v6 resolver on a v4-only chain is a leak when v6 is up and a long
// timeout on every lookup when it is not.
func chainFilterDNS(servers []net.IP, allowV6 bool) []net.IP {
	if allowV6 {
		return servers
	}
	out := make([]net.IP, 0, len(servers))
	for _, ip := range servers {
		if ip == nil {
			continue
		}
		if ip.To4() == nil {
			continue
		}
		out = append(out, ip)
	}
	return out
}

// ChainIPv6Note is what the interface shows about the chain and IPv6.
func ChainIPv6Note(inner *Config) string {
	if ChainConfigHasIPv6(inner) {
		return "IPv6 идёт через цепочку (::/1 + 8000::/1)"
	}
	return "IPv6 у внутреннего звена нет: v6 нужно выключить (awgchain.bat ipv6on)"
}
'@

Write-Go $ipv6Go $goSrc
if (Test-Path -LiteralPath $ipv6Go) { Ok 'conf\chainipv6.go written' } else { Bad 'could not write conf\chainipv6.go' }

$text = [System.IO.File]::ReadAllText($buildGo)
$changed = 0

$a1 = 'hop2.Peers[i].AllowedIPs = chainSplitDefault()'
$n1 = 'hop2.Peers[i].AllowedIPs = chainSplitDefaultFor(&hop2)'
if ($text.Contains($n1)) {
  Ok 'AllowedIPs already cover IPv6, nothing to do'
} elseif ($text.Contains($a1)) {
  Backup-Once $buildGo
  $text = $text.Replace($a1, $n1)
  $changed = $changed + 1
  Ok 'the inner hop now claims the IPv6 halves too'
} else {
  Bad 'anchor not found: chainSplitDefault() call in ChainBuild'
}

$a2 = "`thop2.Peers = chainCopyPeers(inner.Peers)"
$n2 = "`thop2.Interface.DNS = chainFilterDNS(hop2.Interface.DNS, ChainConfigHasIPv6(&hop2))`n`thop2.Peers = chainCopyPeers(inner.Peers)"
if ($text.Contains('chainFilterDNS(hop2.Interface.DNS')) {
  Ok 'the DNS filter is already in place'
} elseif ($text.Contains($a2)) {
  Backup-Once $buildGo
  $text = $text.Replace($a2, $n2)
  $changed = $changed + 1
  Ok 'v6 resolvers are dropped on a v4-only chain'
} else {
  Bad 'anchor not found: chainCopyPeers(inner.Peers) line'
}

if ($changed -gt 0) { Write-Go $buildGo $text }

if ($fails -gt 0) {
  Write-Host 'RESULT=FAIL'
  Write-Host 'Send C:\vpn\logs\patch18-log.txt to the chat.'
  exit 1
}

Write-Host ''
Write-Host 'RESULT=OK'
Write-Host 'Next:  awgchain.bat build   then   awgchain.bat install'
exit 0
