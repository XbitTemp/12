# AwgChain pack 44: copy the freshly built guard over the installed one.
# The old one line copy in awgchain.bat failed with
#   [FAIL] A file could not be copied
# whenever the service had not let go of awgchain-guard.exe yet. This waits
# for the file to become free and tries again instead of failing the build.

param(
  [string]$Src = '',
  [string]$Dst = '',
  [int]$Tries = 12,
  [int]$GapSeconds = 2
)

$ErrorActionPreference = 'Continue'
$q = [char]34
$Src = ('' + $Src).Trim().Trim($q)
$Dst = ('' + $Dst).Trim().Trim($q)

if (-not (Test-Path -LiteralPath $Src)) {
  Write-Host ('[FAIL] the built guard is missing: ' + $Src)
  exit 1
}

$dir = Split-Path -Parent $Dst
if (($dir -ne '') -and -not (Test-Path -LiteralPath $dir)) {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

for ($i = 1; $i -le $Tries; $i++) {
  try {
    Copy-Item -LiteralPath $Src -Destination $Dst -Force -ErrorAction Stop
    $size = (Get-Item -LiteralPath $Dst).Length
    Write-Host ('[OK] guard copied on try ' + $i + ', ' + $size + ' bytes')
    exit 0
  } catch {
    Write-Host ('  try ' + $i + ' of ' + $Tries + ': ' + $_.Exception.Message)
  }
  # Whoever holds the file is usually the guard itself or the manager that
  # just started it. Ask it to go away, politely first.
  if ($i -eq 2) {
    & "$env:SystemRoot\System32\taskkill.exe" /F /IM awgchain-guard.exe 2>&1 | Out-Null
  }
  Start-Sleep -Seconds $GapSeconds
}

Write-Host ('[FAIL] could not copy the guard to ' + $Dst + ' after ' + $Tries + ' tries')
Write-Host '       stop the chain (awgchain.bat down), then build again'
exit 1
