# Classifies the *.conf files in a folder into hop 1 (WARP) and hop 2 (Amnezia)
# and prints two lines that a .bat can consume with for /f:
#   HOP1=<full path>
#   HOP2=<full path>
# Exits 1 with a DIAG line if it cannot decide.

param(
  [Parameter(Mandatory=$true)][string]$Folder
)

$ErrorActionPreference = 'Stop'

$files = @(Get-ChildItem -LiteralPath $Folder -Filter '*.conf' -File -ErrorAction SilentlyContinue)
if ($files.Count -lt 2) {
  Write-Output "DIAG=found $($files.Count) .conf file(s), need two: one WARP, one Amnezia"
  exit 1
}

# Cloudflare WARP anycast ranges seen in the wild, plus the usual WARP address plan
$warpEndpointPattern = '^(162\.159\.(19[0-9]|2[0-9][0-9])\.|188\.114\.9[0-9]\.|162\.159\.4[0-9]\.)'

$scored = @()
foreach ($f in $files) {
  $text = Get-Content -LiteralPath $f.FullName -Raw
  $score = 0
  $endpointHost = ''
  if ($text -match 'Endpoint\s*=\s*([^\s:]+):') { $endpointHost = $Matches[1] }
  if ($endpointHost -match $warpEndpointPattern) { $score += 10 }
  if ($text -match 'Address\s*=\s*172\.16\.') { $score += 5 }
  if ($text -match '2606:4700:') { $score += 5 }
  if ($f.Name -match 'warp') { $score += 3 }
  if ($text -match 'PresharedKey') { $score -= 4 }   # WARP profiles have none
  $scored += [pscustomobject]@{ File = $f.FullName; Score = $score; Host = $endpointHost }
}

$sorted = $scored | Sort-Object -Property Score -Descending
$hop1 = $sorted[0]
$hop2 = $sorted[1]

if ($hop1.Score -le $hop2.Score) {
  Write-Output 'DIAG=could not tell the WARP config from the Amnezia one'
  foreach ($s in $sorted) { Write-Output "DIAG=  $($s.Score)  $($s.Host)  $($s.File)" }
  Write-Output 'DIAG=pass them explicitly: 16-chain-up.bat <warp.conf> <amnezia.conf>'
  exit 1
}
if ($sorted.Count -gt 2) {
  Write-Output "DIAG=more than two .conf files here, using the two best matches"
}

Write-Output "HOP1=$($hop1.File)"
Write-Output "HOP2=$($hop2.File)"
exit 0
