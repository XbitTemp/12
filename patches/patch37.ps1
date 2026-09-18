param([switch]$Revert)
$ErrorActionPreference = 'Continue'

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$core  = 'C:\dev\vpnchain\amneziawg-windows'
$fwDir = Join-Path $core 'tunnel\firewall'
$dest  = Join-Path $fwDir 'chainipv6block.go'

Say 'patch37: IPv6 is stopped with a filter instead of unbinding the adapter'

if ($Revert) {
    if (Test-Path $dest) { Remove-Item $dest -Force; Ok ('removed ' + $dest) }
    Write-Host 'RESULT=OK'
    exit 0
}

if (-not (Test-Path $fwDir)) {
    Bad ('missing: ' + $fwDir)
    Write-Host 'RESULT=FAIL reason=nofile'
    exit 1
}

foreach ($needed in @('chainfirewall.go', 'rules.go', 'helpers.go')) {
    if (-not (Test-Path (Join-Path $fwDir $needed))) {
        Bad ('the firewall package is not the one we know: ' + $needed + ' is missing')
        Write-Host 'RESULT=FAIL reason=nofile'
        exit 1
    }
}

$src = Join-Path $PSScriptRoot 'p55-chainipv6fw.go.txt'
if (-not (Test-Path $src)) {
    Bad 'template missing: p55-chainipv6fw.go.txt'
    Write-Host 'RESULT=FAIL reason=notemplate'
    exit 1
}

[IO.File]::WriteAllBytes($dest, [IO.File]::ReadAllBytes($src))
Ok ('wrote ' + $dest)

Write-Host 'RESULT=OK'
exit 0
