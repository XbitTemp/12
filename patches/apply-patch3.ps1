# Patch #3 for the core repo (amneziawg-windows).
#
# Fix A - the reason hop 2 died with "The parameter is incorrect":
#   configureInterface() is called once per address family. For AF_INET6 it
#   pushes the same MTU onto the IPv6 interface, and Windows rejects any IPv6
#   MTU below 1280 with ERROR_INVALID_PARAMETER (87). The whole interface
#   configuration then fails and the tunnel shuts down - even though the v4
#   side was already configured and the socket was already pinned.
#   A chained tunnel legitimately needs a small MTU, so we clamp only the v6
#   interface and leave the tunnel MTU itself alone.
#
# Fix B - open issue #1: PipePathOfTunnel was missed by the rebrand in patch
#   #2, so our tunnels still opened their UAPI pipe under ...\AmneziaWG\,
#   colliding with the stock client.
#
# Usage:
#   apply-patch3.ps1 -Core C:\dev\vpnchain\amneziawg-windows
#   apply-patch3.ps1 -Core C:\dev\vpnchain\amneziawg-windows -Revert

param(
  [string]$Core = 'C:\dev\vpnchain\amneziawg-windows',
  [switch]$Revert
)

$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)
$suffix = '.orig-patch3'
$failed = $false

$files = @(
  (Join-Path $Core 'tunnel\addressconfig.go'),
  (Join-Path $Core 'services\names.go')
)

if ($Revert) {
  foreach ($f in $files) {
    $b = $f + $suffix
    if (Test-Path -LiteralPath $b) {
      Copy-Item -LiteralPath $b -Destination $f -Force
      Remove-Item -LiteralPath $b -Force
      Write-Host "[OK]   restored $f"
    } else {
      Write-Host "[SKIP] no backup for $f"
    }
  }
  exit 0
}

function Backup-Once {
  param([string]$Path)
  $b = $Path + $suffix
  if (-not (Test-Path -LiteralPath $b)) { Copy-Item -LiteralPath $Path -Destination $b -Force }
}

# ---------------- Fix A: tunnel\addressconfig.go ----------------
$acPath = Join-Path $Core 'tunnel\addressconfig.go'
if (-not (Test-Path -LiteralPath $acPath)) {
  Write-Host "[FAIL] not found: $acPath"
  exit 1
}
$ac = [System.IO.File]::ReadAllText($acPath)

if ($ac -match 'IPv6 minimum') {
  Write-Host '[SKIP] addressconfig.go: the MTU clamp is already there'
} else {
  $pattern = '(?ms)if conf\.Interface\.MTU > 0 \{\s*ipif\.NLMTU = uint32\(conf\.Interface\.MTU\)\s*tun\.ForceMTU\(int\(ipif\.NLMTU\)\)\s*\}'
  if ($ac -notmatch $pattern) {
    Write-Host '[FAIL] addressconfig.go: could not find the MTU block'
    $failed = $true
  } else {
    $new = @(
      "`tif conf.Interface.MTU > 0 {",
      "`t`tmtu := uint32(conf.Interface.MTU)",
      "`t`t// Windows rejects an IPv6 interface MTU below the 1280 byte minimum with",
      "`t`t// ERROR_INVALID_PARAMETER, which fails the whole interface configuration.",
      "`t`t// A tunnel nested inside another tunnel legitimately needs a smaller MTU,",
      "`t`t// so clamp the v6 interface only and keep the tunnel MTU as configured.",
      "`t`tif family == windows.AF_INET6 && mtu < 1280 {",
      "`t`t`tlog.Printf(`"MTU %d is below the IPv6 minimum, leaving the v6 interface MTU unchanged`", mtu)",
      "`t`t} else {",
      "`t`t`tipif.NLMTU = mtu",
      "`t`t}",
      "`t`ttun.ForceMTU(int(conf.Interface.MTU))",
      "`t}"
    ) -join "`r`n"
    Backup-Once $acPath
    $ac = [regex]::Replace($ac, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $new }, 1)
    [System.IO.File]::WriteAllText($acPath, $ac, $enc)
    Write-Host '[OK]   addressconfig.go: v6 MTU below 1280 no longer fails the interface'
  }
}

# ---------------- Fix B: services\names.go ----------------
$nmPath = Join-Path $Core 'services\names.go'
if (-not (Test-Path -LiteralPath $nmPath)) {
  Write-Host "[FAIL] not found: $nmPath"
  $failed = $true
} else {
  $nm = [System.IO.File]::ReadAllText($nmPath)
  if ($nm -match 'Administrators\\AwgChain') {
    Write-Host '[SKIP] names.go: pipe path is already rebranded'
  } elseif ($nm -notmatch 'Administrators\\AmneziaWG') {
    Write-Host '[FAIL] names.go: no pipe path found to rebrand'
    $failed = $true
  } else {
    Backup-Once $nmPath
    $nm = $nm.Replace('Administrators\AmneziaWG', 'Administrators\AwgChain')
    [System.IO.File]::WriteAllText($nmPath, $nm, $enc)
    Write-Host '[OK]   names.go: UAPI pipe path is now ...\Administrators\AwgChain\<tunnel>'
  }
}

if ($failed) { exit 1 }
exit 0
