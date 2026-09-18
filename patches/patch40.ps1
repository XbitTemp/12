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
$tag    = 'p40'

$window = Join-Path $uiDir 'managewindow.go'
$uiFile = Join-Path $uiDir 'ui.go'
$page   = Join-Path $uiDir 'settingspage.go'

Say 'patch40: the Settings tab next to the log, and the lock is lifted when the program is closed for good'

if ($Revert) {
    foreach ($f in @($window, $uiFile)) {
        $b = $f + '.orig-' + $tag
        if (Test-Path $b) { Copy-Item $b $f -Force; Remove-Item $b -Force; Ok ('restored ' + $f) }
    }
    if (Test-Path $page) { Remove-Item $page -Force; Ok ('removed ' + $page) }
    Write-Host 'RESULT=OK'
    exit 0
}

foreach ($f in @($window, $uiFile)) {
    if (-not (Test-Path $f)) { Bad ('missing: ' + $f); Write-Host 'RESULT=FAIL reason=nofile'; exit 1 }
}

$src = Join-Path $PSScriptRoot 'p55-settingspage.go.txt'
if (-not (Test-Path $src)) { Bad 'template missing: p55-settingspage.go.txt'; Write-Host 'RESULT=FAIL reason=notemplate'; exit 1 }
[IO.File]::WriteAllBytes($page, [IO.File]::ReadAllBytes($src))
Ok ('wrote ' + $page)

# managewindow.go: one more tab, and the update tab is found by index
$body = [IO.File]::ReadAllText($window, $enc)
if ($body.Contains('settingsPage')) {
    Ok 'managewindow.go already carries the Settings tab'
} else {
    $aField = $T + 'updatePage  *UpdatePage' + $CRLF
    $aAdd   = $T + 'mtw.tabs.Pages().Add(mtw.logPage.TabPage)' + $CRLF
    $aFound = $T + $T + 'mtw.tabs.Pages().Add(updatePage.TabPage)' + $CRLF
    $aRaise = $T + $T + 'if !mtw.Visible() {' + $CRLF
    $aRaise += $T + $T + $T + 'mtw.tunnelsPage.listView.SelectFirstActiveTunnel()' + $CRLF
    $aRaise += $T + $T + $T + 'if mtw.tabs.Pages().Len() != 3 {' + $CRLF
    $aRaise += $T + $T + $T + $T + 'mtw.tabs.SetCurrentIndex(0)' + $CRLF
    $aRaise += $T + $T + $T + '}' + $CRLF
    $aRaise += $T + $T + '}' + $CRLF
    $aRaise += $T + $T + 'if mtw.tabs.Pages().Len() == 3 {' + $CRLF
    $aRaise += $T + $T + $T + 'mtw.tabs.SetCurrentIndex(2)' + $CRLF
    $aRaise += $T + $T + '}' + $CRLF
    foreach ($a in @($aField, $aAdd, $aFound, $aRaise)) {
        if (-not $body.Contains($a)) { Bad 'an anchor was not found in managewindow.go'; Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }
    }

    $newFields = $aField + $T + 'settingsPage *SettingsPage' + $CRLF + $T + 'updateTabIndex int' + $CRLF
    $body = $body.Replace($aField, $newFields)

    $newTab = $aAdd
    $newTab += $T + 'if settingsPage, settingsErr := NewSettingsPage(); settingsErr == nil {' + $CRLF
    $newTab += $T + $T + 'mtw.settingsPage = settingsPage' + $CRLF
    $newTab += $T + $T + 'mtw.tabs.Pages().Add(settingsPage.TabPage)' + $CRLF
    $newTab += $T + '}' + $CRLF
    $body = $body.Replace($aAdd, $newTab)

    $body = $body.Replace($aFound, $aFound + $T + $T + 'mtw.updateTabIndex = mtw.tabs.Pages().Len() - 1' + $CRLF)

    $newRaise = $T + $T + 'if !mtw.Visible() {' + $CRLF
    $newRaise += $T + $T + $T + 'mtw.tunnelsPage.listView.SelectFirstActiveTunnel()' + $CRLF
    $newRaise += $T + $T + $T + 'if mtw.updatePage == nil {' + $CRLF
    $newRaise += $T + $T + $T + $T + 'mtw.tabs.SetCurrentIndex(0)' + $CRLF
    $newRaise += $T + $T + $T + '}' + $CRLF
    $newRaise += $T + $T + '}' + $CRLF
    $newRaise += $T + $T + 'if mtw.updatePage != nil && mtw.updateTabIndex > 0 {' + $CRLF
    $newRaise += $T + $T + $T + 'mtw.tabs.SetCurrentIndex(mtw.updateTabIndex)' + $CRLF
    $newRaise += $T + $T + '}' + $CRLF
    $body = $body.Replace($aRaise, $newRaise)

    $b = $window + '.orig-' + $tag
    if (-not (Test-Path $b)) { Copy-Item $window $b -Force }
    [IO.File]::WriteAllText($window, $body, $enc)
    Ok 'managewindow.go patched'
}

# ui.go: on the way out, ask the manager to lift the lock
$body = [IO.File]::ReadAllText($uiFile, $enc)
if ($body.Contains('chainLiftLockBeforeQuit')) {
    Ok 'ui.go already lifts the lock on the way out'
} else {
    $aQuit = $T + $T + '_, err := manager.IPCClientQuit(true)' + $CRLF
    if (-not $body.Contains($aQuit)) { Bad 'the quit anchor was not found in ui.go'; Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }
    $body = $body.Replace($aQuit, $T + $T + 'chainLiftLockBeforeQuit()' + $CRLF + $aQuit)
    $b = $uiFile + '.orig-' + $tag
    if (-not (Test-Path $b)) { Copy-Item $uiFile $b -Force }
    [IO.File]::WriteAllText($uiFile, $body, $enc)
    Ok 'ui.go patched'
}

Write-Host 'RESULT=OK'
exit 0
