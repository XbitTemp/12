# AwgChain pack 16: prove that the kill switch really blocks everything but the chain.

param(
	[string]$Hop1 = 'hop1-warp',
	[string]$Hop2 = 'hop2-amnezia',
	[switch]$Flap
)

$ErrorActionPreference = 'Continue'

function Out-Line($text) { Write-Output $text }

Out-Line '=== AwgChain leak test ==='
Out-Line ('date  : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

$guard = Get-Process -Name 'awgchain-guard' -ErrorAction SilentlyContinue
if ($guard) {
	Out-Line ('guard : running, pid ' + $guard.Id)
} else {
	Out-Line 'guard : NOT RUNNING - the kill switch is off, the results below mean nothing'
}

$physical = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
	$_.InterfaceAlias -ne $Hop1 -and $_.InterfaceAlias -ne $Hop2 -and $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*'
} | Select-Object -First 1
if ($physical) {
	Out-Line ('phys  : ' + $physical.IPAddress + ' on ' + $physical.InterfaceAlias)
} else {
	Out-Line 'phys  : not found'
}
Out-Line ''

# --- Test 1: the chain itself still works ---------------------------------
Out-Line '--- test 1: traffic through the chain ---'
$trace = & curl.exe -s --max-time 20 https://www.cloudflare.com/cdn-cgi/trace 2>$null
if ($trace) {
	$traceText = ($trace -join "`n")
	$ipLine = ([regex]::Match($traceText, 'ip=(\S+)')).Groups[1].Value
	$warpLine = ([regex]::Match($traceText, 'warp=(\S+)')).Groups[1].Value
	$coloLine = ([regex]::Match($traceText, 'colo=(\S+)')).Groups[1].Value
	Out-Line ('egress: ' + $ipLine + '  warp=' + $warpLine + '  colo=' + $coloLine)
	Out-Line 'TEST1_CHAIN=PASS'
} else {
	Out-Line 'TEST1_CHAIN=FAIL (no answer - the kill switch may be blocking the chain itself)'
}
Out-Line ''

# --- Test 2: DNS to a foreign resolver must be blocked --------------------
Out-Line '--- test 2: DNS to 8.8.8.8 (must be blocked) ---'
$foreign = $null
try {
	$foreign = Resolve-DnsName -Name 'example.com' -Server '8.8.8.8' -Type A -DnsOnly -QuickTimeout -ErrorAction Stop
} catch {
	$foreign = $null
}
if ($foreign) {
	Out-Line 'TEST2_DNS_FOREIGN=FAIL (8.8.8.8 answered)'
} else {
	Out-Line 'TEST2_DNS_FOREIGN=PASS (blocked)'
}
Out-Line ''

# --- Test 3: DNS to the chain resolver must work --------------------------
Out-Line '--- test 3: DNS to 1.1.1.1 through hop 2 (must work) ---'
$chainDns = $null
try {
	$chainDns = Resolve-DnsName -Name 'example.com' -Server '1.1.1.1' -Type A -DnsOnly -QuickTimeout -ErrorAction Stop
} catch {
	$chainDns = $null
}
if ($chainDns) {
	Out-Line 'TEST3_DNS_CHAIN=PASS'
} else {
	Out-Line 'TEST3_DNS_CHAIN=FAIL (the chain resolver did not answer)'
}
Out-Line ''

# --- Test 4: bypassing the chain over the physical NIC must be blocked ----
Out-Line '--- test 4: direct egress bound to the physical NIC (must be blocked) ---'
if ($physical) {
	$direct = & curl.exe -s --max-time 10 --interface $physical.IPAddress https://api.ipify.org 2>$null
	if ($direct) {
		Out-Line ('TEST4_DIRECT=FAIL (leaked as ' + ($direct -join '') + ')')
	} else {
		Out-Line 'TEST4_DIRECT=PASS (blocked)'
	}
} else {
	Out-Line 'TEST4_DIRECT=SKIP (no physical IPv4 address found)'
}
Out-Line ''

# --- Test 5: IPv6 must be blocked ----------------------------------------
Out-Line '--- test 5: IPv6 egress (must be blocked) ---'
$v6 = & curl.exe -6 -s --max-time 10 https://api64.ipify.org 2>$null
if ($v6) {
	Out-Line ('TEST5_IPV6=FAIL (answered as ' + ($v6 -join '') + ')')
} else {
	Out-Line 'TEST5_IPV6=PASS (blocked)'
}
Out-Line ''

# --- Test 6: the local network stays reachable ----------------------------
Out-Line '--- test 6: local network reachability ---'
$gateway = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -ne $Hop1 -and $_.InterfaceAlias -ne $Hop2 } | Select-Object -First 1
if ($gateway -and $gateway.NextHop -and $gateway.NextHop -ne '0.0.0.0') {
	$ping = Test-Connection -ComputerName $gateway.NextHop -Count 2 -Quiet -ErrorAction SilentlyContinue
	if ($ping) {
		Out-Line ('TEST6_LAN=PASS (' + $gateway.NextHop + ' answers)')
	} else {
		Out-Line ('TEST6_LAN=WARN (' + $gateway.NextHop + ' does not answer; RDP into this machine may be cut)')
	}
} else {
	Out-Line 'TEST6_LAN=SKIP (no physical default gateway found)'
}
Out-Line ''

# --- Test 7 (optional): kill hop 1 and make sure nothing leaks ------------
if ($Flap) {
	Out-Line '--- test 7: hop 1 down, traffic must stop instead of leaking ---'
	$service = 'AwgChainTunnel$' + $Hop1
	& sc.exe stop "$service" | Out-Null
	Start-Sleep -Seconds 6
	$leak = & curl.exe -s --max-time 12 https://api.ipify.org 2>$null
	if ($leak) {
		Out-Line ('TEST7_FLAP=FAIL (leaked as ' + ($leak -join '') + ')')
	} else {
		Out-Line 'TEST7_FLAP=PASS (no traffic at all while hop 1 is down)'
	}
	Out-Line 'restoring hop 1...'
	& sc.exe start "$service" | Out-Null
	Start-Sleep -Seconds 8
	$after = & curl.exe -s --max-time 20 https://www.cloudflare.com/cdn-cgi/trace 2>$null
	if ($after) {
		$afterIp = ([regex]::Match(($after -join "`n"), 'ip=(\S+)')).Groups[1].Value
		Out-Line ('TEST7_RESTORE=PASS (egress ' + $afterIp + ')')
	} else {
		Out-Line 'TEST7_RESTORE=FAIL - run 18-chain-down.bat and then 16-chain-up.bat to rebuild the chain'
	}
	Out-Line ''
}

Out-Line '=== leak test done ==='
