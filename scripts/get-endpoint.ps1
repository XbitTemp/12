# Prints the bare endpoint host of a config, nothing else, so a .bat can
# capture it with for /f. Used to pin a host route for hop 2's endpoint.

param(
  [Parameter(Mandatory=$true)][string]$Source
)

$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $Source -Raw
if ($text -match 'Endpoint\s*=\s*([^\s:]+):(\d+)') {
  Write-Output $Matches[1]
  exit 0
}
exit 1
