# AwgChain DNS lock.
#
# Problem this solves:
#   the chain works, but the physical adapter still carries its own resolvers
#   (8.8.8.8 / 8.8.4.4 on this box) and the NRPT table is empty. While hop 2
#   owns the default route every query happens to travel inside the tunnel,
#   but Windows is free to ask any adapter's resolver at any time - that is
#   what "smart multi-homed name resolution" does, and it fires exactly when
#   the tunnel is slow or flapping. The query then leaves in clear text.
#
# What this script does, in order:
#   1. remembers the current state (per-adapter resolvers + two policy values)
#      in C:\ProgramData\AwgChain\dns-lock-state.json
#   2. installs one NRPT rule for namespace "." pointing at the chain
#      resolvers, so every name, of every process, resolves through hop 2
#   3. rewrites the resolvers on every other adapter so nothing points at a
#      third-party server any more (-FailClosed points them at 127.0.0.1,
#      which means no resolution at all while the chain is down)
#   4. disables smart multi-homed name resolution and parallel A/AAAA queries
#   5. flushes the resolver cache
#
# -Remove puts everything back from the state file.
# -Status prints what is in force right now, used by 21-chain-verify.bat.
#
# This is the user-mode half of the job. The other half - dropping UDP/TCP 53
# and 853 on the physical adapter with WFP - lands with patch #5 (kill
# switch), because only a filter can stop a process that hard-codes its own
# resolver address.

param(
  [string]$Tunnel = 'hop2-amnezia',
  [string[]]$Servers = @(),
  [string]$Hop1 = 'hop1-warp',
  [switch]$FailClosed,
  [switch]$Remove,
  [switch]$Status,
  [string]$StatePath = "$env:ProgramData\AwgChain\dns-lock-state.json"
)

$ErrorActionPreference = 'Continue'
$tag = 'AwgChain DNS lock'
$policyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
$cacheKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'

function Read-Dword([string]$path, [string]$name) {
  if (-not (Test-Path $path)) { return $null }
  $p = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
  if ($null -eq $p) { return $null }
  return [int]$p.$name
}

function Write-Dword([string]$path, [string]$name, [int]$value) {
  if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
  New-ItemProperty -Path $path -Name $name -PropertyType DWord -Value $value -Force | Out-Null
}

function Restore-Dword([string]$path, [string]$name, $value) {
  if ($null -eq $value) {
    if (Test-Path $path) { Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue }
    return
  }
  Write-Dword $path $name ([int]$value)
}

# Static resolvers live in the registry. If NameServer is empty the adapter
# got its resolvers from DHCP, so restoring means "reset", not "set".
function Get-StaticNameServer([string]$guid) {
  if ([string]::IsNullOrEmpty($guid)) { return '' }
  $g = $guid.Trim('{', '}')
  $key = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{$g}"
  if (-not (Test-Path $key)) { return '' }
  $v = (Get-ItemProperty -Path $key -Name 'NameServer' -ErrorAction SilentlyContinue).NameServer
  if ($null -eq $v) { return '' }
  return ([string]$v).Trim()
}

function Get-OtherAdapters([string]$tunnel, [string]$hop1) {
  $res = @()
  foreach ($a in (Get-NetAdapter -ErrorAction SilentlyContinue)) {
    if ($a.Name -eq $tunnel) { continue }
    if ($a.Name -eq $hop1) { continue }
    if ($a.Name -like 'Loopback*') { continue }
    if ($a.Status -ne 'Up') { continue }
    $res += $a
  }
  return $res
}

function Remove-OurNrptRules {
  $n = 0
  foreach ($r in (Get-DnsClientNrptRule -ErrorAction SilentlyContinue)) {
    if ($r.Comment -ne $tag) { continue }
    Remove-DnsClientNrptRule -Name $r.Name -Force -ErrorAction SilentlyContinue
    $n = $n + 1
  }
  return $n
}

# ---------------- status ----------------
if ($Status) {
  Write-Host '--- dns lock status ---'
  $rules = @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue)
  $ours = @()
  foreach ($r in $rules) { if ($r.Comment -eq $tag) { $ours += $r } }
  Write-Host ("NRPTRULES={0} OURS={1}" -f $rules.Count, @($ours).Count)
  foreach ($r in $ours) {
    Write-Host ("  rule {0} namespace '{1}' servers {2}" -f $r.Name, ($r.Namespace -join ','), ($r.NameServers -join ','))
  }
  $sm = Read-Dword $policyKey 'DisableSmartNameResolution'
  $pa = Read-Dword $cacheKey 'DisableParallelAandAAAA'
  if ($null -eq $sm) { $sm = 'unset' }
  if ($null -eq $pa) { $pa = 'unset' }
  Write-Host ("SMARTMULTIHOMED_DISABLED={0}" -f $sm)
  Write-Host ("PARALLEL_AAAA_DISABLED={0}" -f $pa)
  if (Test-Path $StatePath) { Write-Host "STATEFILE=$StatePath" } else { Write-Host 'STATEFILE=none' }
  Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object InterfaceAlias, ServerAddresses |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Host
  exit 0
}

# ---------------- remove ----------------
if ($Remove) {
  $removed = Remove-OurNrptRules
  Write-Host ("removed NRPT rules : {0}" -f $removed)

  if (-not (Test-Path $StatePath)) {
    Write-Host '[WARN] no state file, cannot restore per-adapter resolvers.'
    Write-Host '       If an adapter still points at 127.0.0.1, reset it by hand:'
    Write-Host '         Set-DnsClientServerAddress -InterfaceAlias Ethernet -ResetServerAddresses'
    Restore-Dword $policyKey 'DisableSmartNameResolution' $null
    Restore-Dword $cacheKey 'DisableParallelAandAAAA' $null
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Host 'DNSLOCK=REMOVED_PARTIAL'
    exit 0
  }

  $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
  foreach ($e in $state.interfaces) {
    $alias = [string]$e.alias
    $static = [string]$e.static
    if ([string]::IsNullOrEmpty($static)) {
      Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction SilentlyContinue
      Write-Host ("  {0} -> back to DHCP" -f $alias)
      continue
    }
    $list = @()
    foreach ($s in ($static -split '[,; ]+')) { if (-not [string]::IsNullOrEmpty($s)) { $list += $s } }
    Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $list -ErrorAction SilentlyContinue
    Write-Host ("  {0} -> {1}" -f $alias, ($list -join ','))
  }

  Restore-Dword $policyKey 'DisableSmartNameResolution' $state.smart
  Restore-Dword $cacheKey 'DisableParallelAandAAAA' $state.parallel
  Clear-DnsClientCache -ErrorAction SilentlyContinue
  Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
  Write-Host 'DNSLOCK=REMOVED'
  exit 0
}

# ---------------- apply ----------------
$ad = Get-NetAdapter -Name $Tunnel -ErrorAction SilentlyContinue
if ($null -eq $ad) {
  Write-Host "[FAIL] adapter $Tunnel not found, raise the chain first."
  Write-Host 'DNSLOCK=FAIL'
  exit 1
}
if ($ad.Status -ne 'Up') {
  Write-Host "[FAIL] adapter $Tunnel is $($ad.Status), not Up."
  Write-Host 'DNSLOCK=FAIL'
  exit 1
}

if (@($Servers).Count -eq 0) {
  $Servers = @((Get-DnsClientServerAddress -InterfaceAlias $Tunnel -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
}
$clean = @()
foreach ($s in $Servers) { if (-not [string]::IsNullOrEmpty($s)) { $clean += [string]$s } }
$Servers = $clean
if (@($Servers).Count -eq 0) {
  Write-Host "[WARN] $Tunnel has no resolvers of its own, falling back to 1.1.1.1 / 1.0.0.1"
  $Servers = @('1.1.1.1', '1.0.0.1')
}
Write-Host ("chain resolvers  : {0}" -f ($Servers -join ', '))

# 1. remember what we are about to change, unless a lock is already recorded
if (-not (Test-Path $StatePath)) {
  $ifaces = @()
  foreach ($a in (Get-OtherAdapters $Tunnel $Hop1)) {
    $cur = @((Get-DnsClientServerAddress -InterfaceAlias $a.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
    $ifaces += [pscustomobject]@{
      alias   = $a.Name
      guid    = [string]$a.InterfaceGuid
      static  = (Get-StaticNameServer ([string]$a.InterfaceGuid))
      current = $cur
    }
    Write-Host ("  remembered {0} : {1}" -f $a.Name, ($cur -join ','))
  }
  $state = [pscustomobject]@{
    tunnel     = $Tunnel
    servers    = $Servers
    failClosed = [bool]$FailClosed
    stamp      = (Get-Date).ToString('s')
    interfaces = $ifaces
    smart      = Read-Dword $policyKey 'DisableSmartNameResolution'
    parallel   = Read-Dword $cacheKey 'DisableParallelAandAAAA'
  }
  $dir = Split-Path -Path $StatePath -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $state | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Encoding UTF8
  Write-Host "state saved      : $StatePath"
} else {
  Write-Host "state already saved, keeping the original snapshot: $StatePath"
  $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
}

# 2. one NRPT rule for everything
$dropped = Remove-OurNrptRules
if ($dropped -gt 0) { Write-Host ("replaced {0} stale rule(s)" -f $dropped) }
try {
  Add-DnsClientNrptRule -Namespace '.' -NameServers $Servers -Comment $tag -ErrorAction Stop | Out-Null
  Write-Host "NRPT rule        : '.' -> $($Servers -join ', ')"
} catch {
  Write-Host "[FAIL] could not add the NRPT rule: $($_.Exception.Message)"
  Write-Host 'DNSLOCK=FAIL'
  exit 1
}

# 3. no other adapter may advertise a resolver of its own
$target = $Servers
if ($FailClosed) { $target = @('127.0.0.1') }
foreach ($e in $state.interfaces) {
  $alias = [string]$e.alias
  Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $target -ErrorAction SilentlyContinue
  Write-Host ("  {0} -> {1}" -f $alias, ($target -join ','))
}

# 4. stop Windows from asking every adapter at once
Write-Dword $policyKey 'DisableSmartNameResolution' 1
Write-Dword $cacheKey 'DisableParallelAandAAAA' 1
Write-Host 'smart multi-homed name resolution : disabled'

# 5. nothing cached from before the lock
Clear-DnsClientCache -ErrorAction SilentlyContinue

if ($FailClosed) {
  Write-Host 'mode             : fail closed - names do not resolve while the chain is down'
} else {
  Write-Host 'mode             : fail open - if the chain drops, queries reach the chain resolvers directly'
}
Write-Host 'DNSLOCK=OK'
exit 0
