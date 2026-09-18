param([switch]$Revert)
$ErrorActionPreference = 'Continue'

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$client = 'C:\dev\vpnchain\amneziawg-windows-client'
$uiDir  = Join-Path $client 'ui'
$enc    = New-Object System.Text.UTF8Encoding($false)
$T      = ([char]9).ToString()
$CRLF   = ([char]13).ToString() + ([char]10).ToString()
$Q      = ([char]34).ToString()
$tag    = 'p36'

$confview = Join-Path $uiDir 'confview.go'
$tunnels  = Join-Path $uiDir 'tunnelspage.go'
$panel    = Join-Path $uiDir 'chainpanel.go'
$panelOff = $panel + '.disabled-p55'
$strings  = Join-Path $uiDir 'chainstrings.go'
$protect  = Join-Path $uiDir 'chainprotect.go'
$chainipc = Join-Path $client 'manager\chainipc.go'

Say 'patch36: leak protection line in the Interface box, pack 54 panel removed'

if ($Revert) {
    foreach ($f in @($confview, $tunnels)) {
        $b = $f + '.orig-' + $tag
        if (Test-Path $b) { Copy-Item $b $f -Force; Remove-Item $b -Force; Ok ('restored ' + $f) }
    }
    foreach ($f in @($strings, $protect)) {
        if (Test-Path $f) { Remove-Item $f -Force; Ok ('removed ' + $f) }
    }
    if (Test-Path $panelOff) { Move-Item $panelOff $panel -Force; Ok 'chainpanel.go is back' }
    Write-Host 'RESULT=OK'
    exit 0
}

foreach ($f in @($confview, $tunnels)) {
    if (-not (Test-Path $f)) { Bad ('missing: ' + $f); Write-Host 'RESULT=FAIL reason=nofile'; exit 1 }
}
if (-not (Test-Path $chainipc)) {
    Bad 'manager\chainipc.go from pack 54 is missing, the status channel is needed'
    Write-Host 'RESULT=FAIL reason=nopack54'
    exit 1
}

foreach ($pair in @(@('p55-chainstrings.go.txt', $strings), @('p55-chainprotect.go.txt', $protect))) {
    $src = Join-Path $PSScriptRoot $pair[0]
    if (-not (Test-Path $src)) { Bad ('template missing: ' + $pair[0]); Write-Host 'RESULT=FAIL reason=notemplate'; exit 1 }
    [IO.File]::WriteAllBytes($pair[1], [IO.File]::ReadAllBytes($src))
    Ok ('wrote ' + $pair[1])
}

# confview.go: one more line in the Interface box
$body = [IO.File]::ReadAllText($confview, $enc)
if ($body.Contains('chainProtection')) {
    Ok 'confview.go already carries the protection line'
} else {
    $a1 = $T + 'toggleActive           *toggleActiveLine' + $CRLF
    $a2 = $T + $T + '{l18n.Sprintf(' + $Q + 'DNS servers:' + $Q + '), &iv.dns},' + $CRLF
    $a3 = $T + 'cv.interfaze.apply(&config.Interface)' + $CRLF + $T + 'cv.interfaze.status.update(state)' + $CRLF
    foreach ($a in @($a1, $a2, $a3)) {
        if (-not $body.Contains($a)) { Bad 'an anchor was not found in confview.go'; Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }
    }
    $body = $body.Replace($a1, $T + 'chainProtection        *labelTextLine' + $CRLF + $a1)
    $body = $body.Replace($a2, $a2 + $T + $T + '{chainProtectLabel, &iv.chainProtection},' + $CRLF)
    $body = $body.Replace($a3, $a3 + $T + 'cv.chainApplyProtection(config.Name)' + $CRLF)
    $b = $confview + '.orig-' + $tag
    if (-not (Test-Path $b)) { Copy-Item $confview $b -Force }
    [IO.File]::WriteAllText($confview, $body, $enc)
    Ok 'confview.go patched'
}

# tunnelspage.go: the pack 54 panel goes away
$body = [IO.File]::ReadAllText($tunnels, $enc)
$call = $T + 'tp.chainAttachPanel()' + $CRLF
if ($body.Contains($call)) {
    $b = $tunnels + '.orig-' + $tag
    if (-not (Test-Path $b)) { Copy-Item $tunnels $b -Force }
    $body = $body.Replace($call, '')
    [IO.File]::WriteAllText($tunnels, $body, $enc)
    Ok 'the panel call is removed from tunnelspage.go'
} else {
    Say 'note: no panel call in tunnelspage.go, nothing to remove'
}

if (Test-Path $panel) {
    Move-Item $panel $panelOff -Force
    Ok 'chainpanel.go is set aside as chainpanel.go.disabled-p55'
} else {
    Say 'note: no chainpanel.go here'
}

Write-Host 'RESULT=OK'
exit 0
