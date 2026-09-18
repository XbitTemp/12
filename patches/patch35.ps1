param([switch]$Revert)
$ErrorActionPreference = 'Continue'

$T = ([char]9).ToString()
$CRLF = ([char]13).ToString() + ([char]10).ToString()
$T2 = $T + $T
$T3 = $T + $T + $T
$T4 = $T + $T + $T + $T

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$client = 'C:\dev\vpnchain\amneziawg-windows-client'
$mgrDir = Join-Path $client 'manager'
$uiDir  = Join-Path $client 'ui'
$enc = New-Object System.Text.UTF8Encoding($false)

$ipcServer  = Join-Path $mgrDir 'ipc_server.go'
$chainIpc   = Join-Path $mgrDir 'chainipc.go'
$tunnelPage = Join-Path $uiDir  'tunnelspage.go'
$chainPanel = Join-Path $uiDir  'chainpanel.go'
$chainRoles = Join-Path $uiDir  'chainroles.go'

$tplIpc   = Join-Path $PSScriptRoot 'p54-chainipc.go.txt'
$tplPanel = Join-Path $PSScriptRoot 'p54-chainpanel.go.txt'

function Backup($path) {
    $b = $path + '.orig-p54'
    if (-not (Test-Path $b)) {
        Copy-Item $path $b -Force
        Say ('backup : ' + $b)
    }
}

if ($Revert) {
    foreach ($f in @($ipcServer, $tunnelPage, $chainRoles)) {
        $b = $f + '.orig-p54'
        if (Test-Path $b) {
            Copy-Item $b $f -Force
            Ok ('restored ' + $f)
        } else {
            Say ('no backup for ' + $f)
        }
    }
    foreach ($f in @($chainIpc, $chainPanel)) {
        if (Test-Path $f) {
            Remove-Item $f -Force
            Ok ('removed ' + $f)
        }
    }
    Write-Host 'RESULT=OK'
    exit 0
}

foreach ($f in @($ipcServer, $tunnelPage, $chainRoles, $tplIpc, $tplPanel)) {
    if (-not (Test-Path $f)) {
        Bad ('not found: ' + $f)
        Write-Host 'RESULT=FAIL reason=nofile'
        exit 1
    }
}

# 1. the two new files of the pack
[IO.File]::WriteAllBytes($chainIpc, [IO.File]::ReadAllBytes($tplIpc))
Ok ('wrote ' + $chainIpc)
[IO.File]::WriteAllBytes($chainPanel, [IO.File]::ReadAllBytes($tplPanel))
Ok ('wrote ' + $chainPanel)

# 2. one extra case in the IPC switch of the manager
$text = [IO.File]::ReadAllText($ipcServer, $enc)
if ($text.Contains('ChainStatusMethodType')) {
    Say 'ipc_server.go already answers the chain call'
} else {
    $anchor = $T2 + 'case UpdateMethodType:' + $CRLF + $T3 + 's.Update()' + $CRLF + $T2 + 'default:'
    if (-not $text.Contains($anchor)) {
        Bad 'anchor not found in ipc_server.go'
        Write-Host 'RESULT=FAIL reason=anchor1'
        exit 1
    }
    $insert = $T2 + 'case UpdateMethodType:' + $CRLF + $T3 + 's.Update()' + $CRLF
    $insert = $insert + $T2 + 'case ChainStatusMethodType:' + $CRLF
    $insert = $insert + $T3 + 'err = s.chainServeStatus(encoder)' + $CRLF
    $insert = $insert + $T3 + 'if err != nil {' + $CRLF
    $insert = $insert + $T4 + 'return' + $CRLF
    $insert = $insert + $T3 + '}' + $CRLF
    $insert = $insert + $T2 + 'default:'
    Backup $ipcServer
    $text = $text.Replace($anchor, $insert)
    [IO.File]::WriteAllText($ipcServer, $text, $enc)
    Ok 'ipc_server.go now answers the chain call'
}

# 3. the window builds the panel
$text = [IO.File]::ReadAllText($tunnelPage, $enc)
if ($text.Contains('chainAttachPanel')) {
    Say 'tunnelspage.go already builds the chain panel'
} else {
    $anchor = $T + 'editTunnel.SetVisible(IsAdmin)' + $CRLF + $CRLF + $T + 'disposables.Spare()'
    if (-not $text.Contains($anchor)) {
        Bad 'anchor not found in tunnelspage.go'
        Write-Host 'RESULT=FAIL reason=anchor2'
        exit 1
    }
    $insert = $T + 'editTunnel.SetVisible(IsAdmin)' + $CRLF + $CRLF
    $insert = $insert + $T + 'tp.chainAttachPanel()' + $CRLF + $CRLF
    $insert = $insert + $T + 'disposables.Spare()'
    Backup $tunnelPage
    $text = $text.Replace($anchor, $insert)
    [IO.File]::WriteAllText($tunnelPage, $text, $enc)
    Ok 'tunnelspage.go now builds the chain panel'
}

# 4. the role dialog reads walk answers instead of raw numbers
$text = [IO.File]::ReadAllText($chainRoles, $enc)
if ($text.Contains('walk.DlgCmdYes')) {
    Say 'chainroles.go already reads the walk answers'
} else {
    if (-not $text.Contains('case chainMsgYes:')) {
        Bad 'anchor not found in chainroles.go'
        Write-Host 'RESULT=FAIL reason=anchor3'
        exit 1
    }
    Backup $chainRoles
    $text = $text.Replace($T + 'case chainMsgYes:', $T + 'case walk.DlgCmdYes:')
    $text = $text.Replace($T + 'case chainMsgNo:', $T + 'case walk.DlgCmdNo:')
    $old = 'const chainMsgYes = 6' + $CRLF + 'const chainMsgNo = 7'
    $new = '// Patch 54: the dialog answers come from walk, not from raw numbers.'
    $text = $text.Replace($old, $new)
    [IO.File]::WriteAllText($chainRoles, $text, $enc)
    Ok 'chainroles.go now reads walk.DlgCmdYes and walk.DlgCmdNo'
}

# 5. final check
$bad = 0
if (-not (Test-Path $chainIpc))   { Bad 'chainipc.go is missing';   $bad = 1 }
if (-not (Test-Path $chainPanel)) { Bad 'chainpanel.go is missing'; $bad = 1 }
$text = [IO.File]::ReadAllText($ipcServer, $enc)
if (-not $text.Contains('s.chainServeStatus(encoder)')) { Bad 'ipc_server.go lost the chain case'; $bad = 1 }
$text = [IO.File]::ReadAllText($tunnelPage, $enc)
if (-not $text.Contains('tp.chainAttachPanel()')) { Bad 'tunnelspage.go lost the panel call'; $bad = 1 }
$text = [IO.File]::ReadAllText($chainRoles, $enc)
if (-not $text.Contains('walk.DlgCmdYes')) { Bad 'chainroles.go lost the walk answers'; $bad = 1 }

if ($bad -ne 0) {
    Write-Host 'RESULT=FAIL reason=verify'
    exit 1
}

Ok 'patch 54 is in place, now run: awgchain.bat build, then awgchain.bat install'
Write-Host 'RESULT=OK'
