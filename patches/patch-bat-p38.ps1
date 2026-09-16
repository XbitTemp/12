# AwgChain - patch-bat-p38.ps1
# Adds the pack 38 commands to the installed C:\vpn\awgchain.bat:
#
#   patch18   patch19   ipv6on   ipv6off   ipv6chk   stress   fixconfs
#
# Backup: awgchain.bat.orig-p38. Undo with -Revert. Re-running is safe.

param(
  [string]$Bat = 'C:\vpn\awgchain.bat',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m) }

$Bat = ('' + $Bat).Trim().Trim('"')
if (-not (Test-Path -LiteralPath $Bat)) { Bad ('no ' + $Bat); Write-Host 'RESULT=FAIL'; exit 1 }
$bak = $Bat + '.orig-p38'

if ($Revert) {
  if (Test-Path -LiteralPath $bak) {
    Copy-Item -LiteralPath $bak -Destination $Bat -Force
    Remove-Item -LiteralPath $bak -Force
    Ok 'awgchain.bat restored from awgchain.bat.orig-p38'
    Write-Host 'RESULT=OK'
    exit 0
  }
  Bad 'no backup awgchain.bat.orig-p38'
  Write-Host 'RESULT=FAIL'
  exit 1
}

$text = [System.IO.File]::ReadAllText($Bat)
if ($text.Contains(':cmd_patch18')) {
  Ok 'pack 38 commands are already in awgchain.bat'
  Write-Host 'RESULT=OK'
  exit 0
}
if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $Bat -Destination $bak -Force; Ok 'backup saved as awgchain.bat.orig-p38' }

$nl = "`r`n"

# 1 - the command whitelist
$validOld = 'patch16 patch17 autoguard'
$validNew = 'patch16 patch17 patch18 patch19 ipv6on ipv6off ipv6chk stress fixconfs autoguard'
if ($text.Contains($validOld)) {
  $text = $text.Replace($validOld, $validNew)
  Ok 'command whitelist extended'
} else {
  Bad 'could not find the VALID list, the new commands may not be accepted'
}

# 2 - menu lines and their numbers
$menuAnchor = 'echo    33  patch17    show the WARP half in the editor (patch 17)'
$menuNew = $menuAnchor + $nl +
  'echo    35  patch18    IPv6 goes through the chain (patch 18)' + $nl +
  'echo    36  patch19    ask which config is WARP, honest MTU text (patch 19)' + $nl +
  'echo    37  ipv6on     lock IPv6 outside the chain' + $nl +
  'echo    38  ipv6off    unlock IPv6' + $nl +
  'echo    39  ipv6chk    IPv6 leak check, 6 tests' + $nl +
  'echo    40  stress     50 on/off cycles with a CSV report' + $nl +
  'echo    41  fixconfs   normalise MTU in the source configs'
if ($text.Contains($menuAnchor)) {
  $text = $text.Replace($menuAnchor, $menuNew)
  Ok 'menu entries 35-41 added'
} else {
  Bad 'menu anchor not found, entries not added (commands still work by name)'
}

$selAnchor = 'if "%SEL%"=="33" set "CMD=patch17"'
$selNew = $selAnchor + $nl +
  'if "%SEL%"=="35" set "CMD=patch18"' + $nl +
  'if "%SEL%"=="36" set "CMD=patch19"' + $nl +
  'if "%SEL%"=="37" set "CMD=ipv6on"' + $nl +
  'if "%SEL%"=="38" set "CMD=ipv6off"' + $nl +
  'if "%SEL%"=="39" set "CMD=ipv6chk"' + $nl +
  'if "%SEL%"=="40" set "CMD=stress"' + $nl +
  'if "%SEL%"=="41" set "CMD=fixconfs"'
if ($text.Contains($selAnchor)) {
  $text = $text.Replace($selAnchor, $selNew)
  Ok 'menu numbers wired to the commands'
} else {
  Bad 'menu number anchor not found'
}

# 3 - the command blocks themselves
$blocks = @()
$blocks = $blocks + 'rem ========================= pack 38 commands ============================='
$blocks = $blocks + ':cmd_patch18'
$blocks = $blocks + 'set "LOG=%LOGS%\patch18-log.txt"'
$blocks = $blocks + 'if not exist "%HERE%patch18.ps1" goto nop38'
$blocks = $blocks + 'echo ==== %DATE% %TIME% patch18 %A2% ====> "%LOG%"'
$blocks = $blocks + 'set "P38ARG="'
$blocks = $blocks + 'if /i "%A2%"=="revert" set "P38ARG=-Revert"'
$blocks = $blocks + 'powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch18.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P38ARG% >> "%LOG%" 2>&1'
$blocks = $blocks + 'type "%LOG%"'
$blocks = $blocks + 'echo Log: %LOG%'
$blocks = $blocks + 'goto end'
$blocks = $blocks + ''
$blocks = $blocks + ':cmd_patch19'
$blocks = $blocks + 'set "LOG=%LOGS%\patch19-log.txt"'
$blocks = $blocks + 'if not exist "%HERE%patch19.ps1" goto nop38'
$blocks = $blocks + 'echo ==== %DATE% %TIME% patch19 %A2% ====> "%LOG%"'
$blocks = $blocks + 'set "P39ARG="'
$blocks = $blocks + 'if /i "%A2%"=="revert" set "P39ARG=-Revert"'
$blocks = $blocks + 'powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch19.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P39ARG% >> "%LOG%" 2>&1'
$blocks = $blocks + 'type "%LOG%"'
$blocks = $blocks + 'echo Log: %LOG%'
$blocks = $blocks + 'goto end'
$blocks = $blocks + ''
$blocks = $blocks + ':cmd_ipv6on'
$blocks = $blocks + 'set "LOG=%LOGS%\ipv6-log.txt"'
$blocks = $blocks + 'if not exist "%HERE%ipv6-lock.ps1" goto nop38'
$blocks = $blocks + 'echo ==== %DATE% %TIME% ipv6 on ====> "%LOG%"'
$blocks = $blocks + 'powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%ipv6-lock.ps1" -On >> "%LOG%" 2>&1'
$blocks = $blocks + 'type "%LOG%"'
$blocks = $blocks + 'goto end'
$blocks = $blocks + ''
$blocks = $blocks + ':cmd_ipv6off'
$blocks = $blocks + 'set "LOG=%LOGS%\ipv6-log.txt"'
$blocks = $blocks + 'if not exist "%HERE%ipv6-lock.ps1" goto nop38'
$blocks = $blocks + 'echo ==== %DATE% %TIME% ipv6 off ====> "%LOG%"'
$blocks = $blocks + 'powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%ipv6-lock.ps1" -Off >> "%LOG%" 2>&1'
$blocks = $blocks + 'type "%LOG%"'
$blocks = $blocks + 'goto end'
$blocks = $blocks + ''
$blocks = $blocks + ':cmd_ipv6chk'
$blocks = $blocks + 'set "LOG=%LOGS%\ipv6-check-log.txt"'
$blocks = $blocks + 'if not exist "%HERE%ipv6-check.ps1" goto nop38'
$blocks = $blocks + 'echo ==== %DATE% %TIME% ipv6 check ====> "%LOG%"'
$blocks = $blocks + 'powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%ipv6-check.ps1" -Here "%HERE0%" >> "%LOG%" 2>&1'
$blocks = $blocks + 'type "%LOG%"'
$blocks = $blocks + 'echo Log: %LOG%'
$blocks = $blocks + 'goto end'
$blocks = $blocks + ''
$blocks = $blocks + ':cmd_stress'
$blocks = $blocks + 'set "LOG=%LOGS%\stress-chain-log.txt"'
$blocks = $blocks + 'if not exist "%HERE%stress-chain.ps1" goto nop38'
$blocks = $blocks + 'set "CYC=%A2%"'
$blocks = $blocks + 'if "%CYC%"=="" set "CYC=50"'
$blocks = $blocks + 'set "SMODE=%A3%"'
$blocks = $blocks + 'if "%SMODE%"=="" set "SMODE=ordered"'
$blocks = $blocks + 'echo Running %CYC% cycles in mode %SMODE%, this takes a while.'
$blocks = $blocks + 'powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%stress-chain.ps1" -Cycles %CYC% -Mode %SMODE% -Here "%HERE0%" -Logs "%LOGS%"'
$blocks = $blocks + 'echo Report: %LOGS%\stress-chain.csv'
$blocks = $blocks + 'goto end'
$blocks = $blocks + ''
$blocks = $blocks + ':cmd_fixconfs'
$blocks = $blocks + 'set "LOG=%LOGS%\fixconfs-log.txt"'
$blocks = $blocks + 'if not exist "%HERE%fix-confs.ps1" goto nop38'
$blocks = $blocks + 'set "FCARG="'
$blocks = $blocks + 'if /i "%A2%"=="revert" set "FCARG=-Revert"'
$blocks = $blocks + 'echo ==== %DATE% %TIME% fixconfs %A2% ====> "%LOG%"'
$blocks = $blocks + 'powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%fix-confs.ps1" -Folder "%HERE0%" %FCARG% >> "%LOG%" 2>&1'
$blocks = $blocks + 'type "%LOG%"'
$blocks = $blocks + 'goto end'
$blocks = $blocks + ''
$blocks = $blocks + ':nop38'
$blocks = $blocks + 'echo [FAIL] a pack 38 script is missing next to this file: %HERE%'
$blocks = $blocks + 'echo Unpack the pack 38 zip into C:\vpn with replace and try again.'
$blocks = $blocks + 'goto end'
$blocks = $blocks + ''
$blockText = ($blocks -join $nl) + $nl

$insertAnchor = ':cmd_logs'
$idx = $text.IndexOf($insertAnchor)
if ($idx -lt 0) {
  Bad 'could not find :cmd_logs to insert the new blocks before'
  Write-Host 'RESULT=FAIL'
  exit 1
}
$text = $text.Substring(0, $idx) + $blockText + $text.Substring($idx)
Ok 'command blocks inserted'

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Bat, $text, $enc)

Write-Host ''
Write-Host 'RESULT=OK'
Write-Host 'Check it with:  awgchain.bat vars'
exit 0
