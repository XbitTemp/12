param([switch]$Revert)
$ErrorActionPreference = 'Continue'

$here = $PSScriptRoot
$list = @('patch36.ps1', 'patch37.ps1', 'patch38.ps1', 'patch39.ps1', 'patch40.ps1')
if ($Revert) { [array]::Reverse($list) }

Write-Host '=== AwgChain pack 55 ==='
if ($Revert) { Write-Host 'mode: revert' } else { Write-Host 'mode: apply' }

foreach ($p in $list) {
    $full = Join-Path $here $p
    if (-not (Test-Path $full)) {
        Write-Host ('[FAIL] missing ' + $p)
        Write-Host 'RESULT=FAIL reason=nofile'
        exit 1
    }
    Write-Host ''
    Write-Host ('--- ' + $p + ' ---')
    if ($Revert) { & $full -Revert } else { & $full }
    if ($LASTEXITCODE -ne 0) {
        Write-Host ('[FAIL] ' + $p + ' stopped the run')
        Write-Host 'RESULT=FAIL reason=patch'
        exit 1
    }
}

Write-Host ''
Write-Host '[OK] pack 55 is in the sources, now build and install'
Write-Host 'RESULT=OK'
exit 0
