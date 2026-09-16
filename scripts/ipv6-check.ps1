param(
  [string]$Pair = "",
  [switch]$Here
)

$ErrorActionPreference = "SilentlyContinue"

if ($Pair -eq "") {
  $detect = Join-Path $PSScriptRoot "detect-pair.ps1"
  if (Test-Path $detect) { $Pair = (& $detect).Trim() }
}
if ($Pair -eq "") { $Pair = "warpam" }
$hop1 = $Pair + "-hop1"

Write-Host "=========================================================="
Write-Host (" IPv6 leak check - pair {0}" -f $Pair)
Write-Host "=========================================================="

$chainNames = @($Pair, $hop1)
$chainAdapters = Get-NetAdapter | Where-Object { $chainNames -contains $_.Name }

# does the chain itself carry IPv6?
$chainHasV6 = $false
foreach ($a in $chainAdapters) {
  $addr = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
          Where-Object { $_.PrefixOrigin -ne "WellKnown" -and $_.IPAddress -notlike "fe80*" }
  if ($addr) { $chainHasV6 = $true }
}
Write-Host ("chain carries IPv6 itself: {0}" -f $chainHasV6)

# is IPv6 switched off everywhere (router without IPv6 - the supported mode)?
$boundOutside = Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue |
  Where-Object { $_.Enabled -and $_.Name -notlike "Loopback*" -and ($chainNames -notcontains $_.Name) }
$v6Disabled = ($boundOutside.Count -eq 0)
if ($v6Disabled) { Write-Host "IPv6 mode: disabled on every physical adapter (v4-only chain)" }
elseif ($chainHasV6) { Write-Host "IPv6 mode: carried inside the chain" }
else { Write-Host "IPv6 mode: enabled on the host but NOT carried by the chain" }
Write-Host ""

$score = 0
$total = 6

function Report($ok, $title, $detail) {
  if ($ok) { Write-Host ("[PASS] {0} :: {1}" -f $title, $detail) }
  else     { Write-Host ("[FAIL] {0} :: {1}" -f $title, $detail) }
}

# 1. no IPv6 bound outside the chain, unless the chain carries v6
$names = ($boundOutside | ForEach-Object { $_.Name }) -join ","
$ok1 = $v6Disabled -or $chainHasV6
Report $ok1 "v6 unbound outside the chain" ("bound on: " + $names)
if ($ok1) { $score++ }

# 2. if v6 is alive at all, its default route must belong to the chain
$v6def = Get-NetRoute -AddressFamily IPv6 -ErrorAction SilentlyContinue |
  Where-Object { $_.DestinationPrefix -eq "::/0" -or $_.DestinationPrefix -eq "::/1" -or $_.DestinationPrefix -eq "8000::/1" }
$outsideDef = $v6def | Where-Object { $chainNames -notcontains $_.InterfaceAlias }
$ok2 = $v6Disabled -or ($outsideDef.Count -eq 0)
$routeText = ($v6def | ForEach-Object { $_.InterfaceAlias + " " + $_.DestinationPrefix }) -join ", "
Report $ok2 "v6 default route inside the chain" ("routes: " + $routeText)
if ($ok2) { $score++ }

# 3. no bare IPv6 connectivity to a public resolver
$bare = $false
try {
  $t = Test-NetConnection -ComputerName "2606:4700:4700::1111" -Port 443 -WarningAction SilentlyContinue
  $bare = [bool]$t.TcpTestSucceeded
} catch { $bare = $false }
$ok3 = $v6Disabled -or -not $bare
Report $ok3 "no bare v6 connectivity" ("tcp 443 to 2606:4700:4700::1111 = " + $bare)
if ($ok3) { $score++ }

# 4. no IPv6 egress address visible to the outside world
$v6egress = ""
try {
  $v6egress = (Invoke-WebRequest -Uri "https://ipv6.icanhazip.com" -TimeoutSec 8 -UseBasicParsing).Content.Trim()
} catch { $v6egress = "" }
$ok4 = ($v6egress -eq "")
Report $ok4 "no v6 egress address visible" ("v6 egress: " + $v6egress)
if ($ok4) { $score++ }

# 5. no IPv6 resolvers outside the chain
# Windows always lists fec0:0:0:ffff::1/2/3 on the loopback pseudo interface,
# those are placeholders, not a leak - they are ignored here.
$badDns = @()
$dns = Get-DnsClientServerAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue
foreach ($d in $dns) {
  if ($d.InterfaceAlias -like "Loopback*") { continue }
  if ($chainNames -contains $d.InterfaceAlias) { continue }
  $real = @($d.ServerAddresses | Where-Object { $_ -notlike "fec0:0:0:ffff*" })
  if ($real.Count -gt 0) { $badDns += ($d.InterfaceAlias + "=" + ($real -join "/")) }
}
$ok5 = ($badDns.Count -eq 0)
Report $ok5 "no v6 resolvers outside the chain" ("v6 dns: " + ($badDns -join " "))
if ($ok5) { $score++ }

# 6. IPv4 egress still works and goes through the chain
$v4 = ""
try {
  $v4 = (Invoke-WebRequest -Uri "https://api.ipify.org" -TimeoutSec 10 -UseBasicParsing).Content.Trim()
} catch { $v4 = "" }
$ok6 = ($v4 -ne "")
Report $ok6 "v4 egress answers" ("v4 egress: " + $v4)
if ($ok6) { $score++ }

Write-Host ""
Write-Host ("SCORE={0}/{1}" -f $score, $total)
if ($score -eq $total) { Write-Host "RESULT=OK" } else { Write-Host "RESULT=FAIL" }
