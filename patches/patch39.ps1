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
$tag    = 'p39'

$dialog = Join-Path $uiDir 'editdialog.go'
$checks = Join-Path $uiDir 'chainchecks.go'

Say 'patch39: three check boxes in the tunnel editor, the old one now drives our kill switch'

if ($Revert) {
    $b = $dialog + '.orig-' + $tag
    if (Test-Path $b) { Copy-Item $b $dialog -Force; Remove-Item $b -Force; Ok ('restored ' + $dialog) }
    if (Test-Path $checks) { Remove-Item $checks -Force; Ok ('removed ' + $checks) }
    Write-Host 'RESULT=OK'
    exit 0
}

if (-not (Test-Path $dialog)) { Bad ('missing: ' + $dialog); Write-Host 'RESULT=FAIL reason=nofile'; exit 1 }

$src = Join-Path $PSScriptRoot 'p55-chainchecks.go.txt'
if (-not (Test-Path $src)) { Bad 'template missing: p55-chainchecks.go.txt'; Write-Host 'RESULT=FAIL reason=notemplate'; exit 1 }
[IO.File]::WriteAllBytes($checks, [IO.File]::ReadAllBytes($src))
Ok ('wrote ' + $checks)

$body = [IO.File]::ReadAllText($dialog, $enc)
if ($body.Contains('chainExtraChecks')) {
    Ok 'editdialog.go already carries the three boxes'
    Write-Host 'RESULT=OK'
    exit 0
}

$aFields = $T + 'blockUntunneledTraficCheckGuard bool' + $CRLF
$aMake   = $T + 'if dlg.blockUntunneledTrafficCB, err = walk.NewCheckBox(buttonsContainer); err != nil {' + $CRLF
$aHide   = $T + 'dlg.blockUntunneledTrafficCB.SetVisible(false)' + $CRLF
$aAttach = $T + 'dlg.blockUntunneledTrafficCB.CheckedChanged().Attach(dlg.onBlockUntunneledTrafficCBCheckedChanged)' + $CRLF
$aOld1   = 'func (dlg *EditDialog) onBlockUntunneledTrafficCBCheckedChanged() {'
$aOld2   = 'func (dlg *EditDialog) onBlockUntunneledTrafficStateChanged(state int) {'
$aSave   = $T + 'dlg.config = *cfg' + $CRLF + $T + 'dlg.Accept()' + $CRLF

foreach ($a in @($aFields, $aMake, $aHide, $aAttach, $aOld1, $aOld2, $aSave)) {
    if (-not $body.Contains($a)) { Bad 'an anchor was not found in editdialog.go'; Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }
}

$fields = $T + 'chainChecks                     walk.Container' + $CRLF
$fields += $T + 'chainIPv6CB                     *walk.CheckBox' + $CRLF
$fields += $T + 'chainLANCB                      *walk.CheckBox' + $CRLF
$body = $body.Replace($aFields, $aFields + $fields)

$body = $body.Replace($aMake, $T + 'if dlg.blockUntunneledTrafficCB, err = walk.NewCheckBox(chainChecksBox(dlg, buttonsContainer)); err != nil {' + $CRLF)
$body = $body.Replace($aHide, $T + 'dlg.blockUntunneledTrafficCB.SetVisible(true)' + $CRLF)

$after = $T + 'dlg.blockUntunneledTrafficCB.SetText(chainCheckLockLabel)' + $CRLF
$after += $T + 'dlg.blockUntunneledTrafficCB.SetToolTipText(chainCheckLockHint)' + $CRLF
$after += $T + 'if err = chainExtraChecks(dlg); err != nil {' + $CRLF
$after += $T + $T + 'return nil, err' + $CRLF
$after += $T + '}' + $CRLF
$body = $body.Replace($aAttach, $aAttach + $after)

$body = $body.Replace($aOld1, 'func (dlg *EditDialog) chainLegacyBlockToggle() {')
$body = $body.Replace($aOld2, 'func (dlg *EditDialog) chainLegacyBlockStateChanged(state int) {')

$body = $body.Replace($aSave, $T + 'dlg.chainSaveChecks(newName)' + $CRLF + $aSave)

$b = $dialog + '.orig-' + $tag
if (-not (Test-Path $b)) { Copy-Item $dialog $b -Force }
[IO.File]::WriteAllText($dialog, $body, $enc)
Ok 'editdialog.go patched'

Write-Host 'RESULT=OK'
exit 0
