param([switch]$Revert)
$ErrorActionPreference = 'Continue'

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[FAIL] ' + $t) }

$client = 'C:\dev\vpnchain\amneziawg-windows-client'
$mgrDir = Join-Path $client 'manager'
$enc    = New-Object System.Text.UTF8Encoding($false)
$T      = ([char]9).ToString()
$CRLF   = ([char]13).ToString() + ([char]10).ToString()
$LF     = ([char]10).ToString()
$Q      = ([char]34).ToString()
$tag    = 'p38'

$lock     = Join-Path $mgrDir 'chainlock.go'
$server   = Join-Path $mgrDir 'ipc_server.go'
$settings = Join-Path $mgrDir 'chainsettings.go'
$setipc   = Join-Path $mgrDir 'chainsettingsipc.go'

Say 'patch38: the manager keeps the settings and obeys them'

if ($Revert) {
    foreach ($f in @($lock, $server)) {
        $b = $f + '.orig-' + $tag
        if (Test-Path $b) { Copy-Item $b $f -Force; Remove-Item $b -Force; Ok ('restored ' + $f) }
    }
    foreach ($f in @($settings, $setipc)) {
        if (Test-Path $f) { Remove-Item $f -Force; Ok ('removed ' + $f) }
    }
    Write-Host 'RESULT=OK'
    exit 0
}

foreach ($f in @($lock, $server)) {
    if (-not (Test-Path $f)) { Bad ('missing: ' + $f); Write-Host 'RESULT=FAIL reason=nofile'; exit 1 }
}

foreach ($pair in @(@('p55-chainsettings.go.txt', $settings), @('p55-chainsettingsipc.go.txt', $setipc))) {
    $src = Join-Path $PSScriptRoot $pair[0]
    if (-not (Test-Path $src)) { Bad ('template missing: ' + $pair[0]); Write-Host 'RESULT=FAIL reason=notemplate'; exit 1 }
    [IO.File]::WriteAllBytes($pair[1], [IO.File]::ReadAllBytes($src))
    Ok ('wrote ' + $pair[1])
}

# chainlock.go: the lock now asks the settings first
$body = [IO.File]::ReadAllText($lock, $enc)
if ($body.Contains('ChainSettingsFor')) {
    Ok 'chainlock.go already asks the settings'
} else {
    $head = 'func chainArmLockInProc(leaf string) bool {' + $LF + $T + 'if chainInProcLockDisabled() {' + $LF
    $off  = $T + 'if !ChainSettingsFor(leaf).KillSwitch {' + $LF
    $off += $T + $T + 'log.Printf(' + $Q + '[AwgChain] The kill switch is switched off in the settings of %s' + $Q + ', leaf)' + $LF
    $off += $T + $T + 'chainApplyIPv6For(leaf)' + $LF
    $off += $T + $T + 'return true' + $LF
    $off += $T + '}' + $LF + $LF
    $lans = $T + $T + 'AllowedLANs:  chainLockLANs(root),' + $LF
    $arm  = $T + 'go chainLockWatchStopEvent(stop)' + $LF
    $drop = $T + 'firewall.DisableChainFirewall()' + $LF + $T + 'log.Printf(' + $Q + '[AwgChain] Kill switch lifted, the machine is open again' + $Q + ')' + $LF
    foreach ($a in @($head, $lans, $arm, $drop)) {
        if (-not $body.Contains($a)) { Bad 'an anchor was not found in chainlock.go'; Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }
    }
    $body = $body.Replace($head, 'func chainArmLockInProc(leaf string) bool {' + $LF + $off + $T + 'if chainInProcLockDisabled() {' + $LF)
    $body = $body.Replace($lans, $T + $T + 'AllowedLANs:  chainSettingsLANs(root, leaf),' + $LF)
    $body = $body.Replace($arm, $T + 'chainApplyIPv6For(leaf)' + $LF + $arm)
    $body = $body.Replace($drop, $drop + $T + 'chainDropIPv6Block()' + $LF)
    $b = $lock + '.orig-' + $tag
    if (-not (Test-Path $b)) { Copy-Item $lock $b -Force }
    [IO.File]::WriteAllText($lock, $body, $enc)
    Ok 'chainlock.go patched'
}

# ipc_server.go: five more methods and the raise at start
$body = [IO.File]::ReadAllText($server, $enc)
if ($body.Contains('ChainSettingsGetMethodType')) {
    Ok 'ipc_server.go already serves the settings'
} else {
    $cases = $T + $T + 'case UpdateMethodType:' + $CRLF + $T + $T + $T + 's.Update()' + $CRLF
    if (-not $body.Contains($cases)) { Bad 'the switch anchor was not found in ipc_server.go'; Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }
    $add = ''
    foreach ($m in @(@('ChainSettingsGetMethodType', 's.chainServeSettingsGet(decoder, encoder)'), @('ChainSettingsSetMethodType', 's.chainServeSettingsSet(decoder, encoder)'), @('ChainGlobalGetMethodType', 's.chainServeGlobalGet(encoder)'), @('ChainGlobalSetMethodType', 's.chainServeGlobalSet(decoder, encoder)'), @('ChainLiftLockMethodType', 's.chainServeLiftLock(encoder)'))) {
        $add += $T + $T + 'case ' + $m[0] + ':' + $CRLF
        $add += $T + $T + $T + 'if chainErr := ' + $m[1] + '; chainErr != nil {' + $CRLF
        $add += $T + $T + $T + $T + 'return' + $CRLF
        $add += $T + $T + $T + '}' + $CRLF
    }
    $body = $body.Replace($cases, $cases + $add)

    $listen = $T + 'service := &ManagerService{' + $CRLF + $T + $T + 'events:        events,' + $CRLF + $T + $T + 'elevatedToken: elevatedToken,' + $CRLF + $T + '}' + $CRLF
    if ($body.Contains($listen)) {
        $body = $body.Replace($listen, $listen + $T + 'go service.chainAutoRaiseOnStart()' + $CRLF)
        Ok 'the raise at start is wired into IPCServerListen'
    } else {
        Say 'note: IPCServerListen looks different, the raise at start is skipped'
    }

    $b = $server + '.orig-' + $tag
    if (-not (Test-Path $b)) { Copy-Item $server $b -Force }
    [IO.File]::WriteAllText($server, $body, $enc)
    Ok 'ipc_server.go patched'
}

Write-Host 'RESULT=OK'
exit 0
