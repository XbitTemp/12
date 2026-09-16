param(
	[string]$Bat = 'C:\vpn\awgchain.bat',
	[switch]$Revert
)

$ErrorActionPreference = 'Stop'
$script:fails = 0

function Say($m) { Write-Host $m }
function Ok($m) { Write-Host ('[OK] ' + $m) }
function Bad($m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }
function Crlf($s) { return (($s -replace "`r`n", "`n") -replace "`n", "`r`n") }

Say ('control panel: ' + $Bat)

if (-not (Test-Path -LiteralPath $Bat)) {
	Bad ('there is no such file: ' + $Bat)
	Write-Host 'RESULT=FAIL'
	exit 1
}

$backup = $Bat + '.orig-p37'

if ($Revert) {
	if (Test-Path -LiteralPath $backup) {
		Copy-Item -LiteralPath $backup -Destination $Bat -Force
		Ok 'the control panel is back to the version from before patch 37'
		Write-Host 'RESULT=REVERTED'
		exit 0
	}
	Bad 'there is no backup to go back to'
	Write-Host 'RESULT=FAIL'
	exit 1
}

if (-not (Test-Path -LiteralPath $backup)) {
	Copy-Item -LiteralPath $Bat -Destination $backup -Force
	Ok ('backup written: ' + $backup)
}
else {
	Ok 'the backup was already there'
}

$script:t = [IO.File]::ReadAllText($Bat)
Say ('size before: ' + $script:t.Length + ' bytes')

$here = Split-Path -Parent $Bat
if (Test-Path -LiteralPath (Join-Path $here 'detect-pair.ps1')) {
	Ok 'detect-pair.ps1 is next to the control panel'
}
else {
	Bad 'detect-pair.ps1 is missing - unzip the whole pack into the same folder'
}

# ---------------------------------------------------------------- scratch file
if ($script:t.Contains('TMPTXT')) {
	Ok 'the scratch variable was already there'
}
else {
	$anchor = 'set "LOGS=%HERE%logs"' + "`r`n"
	if ($script:t.Contains($anchor)) {
		$script:t = $script:t.Replace($anchor, $anchor + 'set "TMPTXT=%TEMP%\awgchain-scratch.txt"' + "`r`n")
		Ok 'added the scratch variable'
	}
	else {
		Bad 'could not find the LOGS line in the header'
	}
}

# ------------------------------------------------------------ pair detection
$newpair = Crlf @'

:detectpair
rem  Figures out which pair of tunnels to work with. Override by hand:
rem     set AWGCHAIN_PAIR=warpam1
set "PAIRSRC=detect-pair.ps1"
set "PAIR=%AWGCHAIN_PAIR%"
if not "%PAIR%"=="" goto dpsrcenv
if not exist "%HERE%detect-pair.ps1" goto dpclean
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%detect-pair.ps1" -Data "%DATA%"`) do set "PAIR=%%P"
goto dpclean
:dpsrcenv
set "PAIRSRC=the AWGCHAIN_PAIR variable"
:dpclean
set "PAIR=%PAIR: =%"
if not "%PAIR%"=="" goto dpapply
set "PAIRSRC=fallback to the old console names"
set "PAIR=hop2-amnezia"
:dpapply
set "N2=%PAIR%"
set "N1=%PAIR%-hop1"
if /i "%PAIR%"=="hop2-amnezia" set "N1=hop1-warp"
:dpnames
set "C1=%DATA%\%N1%.conf"
set "C2=%DATA%\%N2%.conf"
set "S1=AwgChainTunnel$%N1%"
set "S2=AwgChainTunnel$%N2%"
exit /b 0
'@

if ($script:t.Contains('set "PAIRSRC=')) {
	Ok 'the pair detection had already been rewritten'
}
else {
	$i = $script:t.IndexOf("`r`n:detectpair`r`n")
	$j = $script:t.IndexOf("`r`n:freebin`r`n")
	if ($i -ge 0 -and $j -gt $i) {
		$script:t = $script:t.Substring(0, $i) + $newpair + $script:t.Substring($j)
		Ok 'the pair detection now runs detect-pair.ps1 (no more broken one-liner)'
	}
	else {
		Bad 'could not find the :detectpair block'
	}
}

# ------------------------------------------------------------- say / chk
$helpers = Crlf @'
:say
set "MSG=%~1"
if not defined MSG goto sayblank
echo %MSG%
if defined LOG echo %MSG%>> "%LOG%"
exit /b 0
:sayblank
echo.
if defined LOG echo.>> "%LOG%"
exit /b 0

:chk
set "CHKP=%~1"
set "CHKT=%~2"
if exist "%CHKP%" goto chkok
call :say "  [MISSING] %CHKT%  ->  %CHKP%"
exit /b 0
:chkok
call :say "  [ok]      %CHKT%"
exit /b 0

'@

if ($script:t.Contains("`r`n:chk`r`n")) {
	Ok 'the say/chk helpers were already there'
}
else {
	$anchor = "`r`n:goenv`r`n"
	if ($script:t.Contains($anchor)) {
		$script:t = $script:t.Replace($anchor, "`r`n" + $helpers + ":goenv`r`n")
		Ok 'added the say/chk helpers'
	}
	else {
		Bad 'could not find the :goenv helper'
	}
}

# --------------------------------------------------------------- vars screen
$vars = Crlf @'
rem ==========================================================================
rem  VARS - every variable plus a self-check of the whole toolbox
rem ==========================================================================
:cmd_vars
set "LOG=%LOGS%\vars-log.txt"
echo ==== %DATE% %TIME% vars ====> "%LOG%"
call :say "=========================================================='"
call :say " AwgChain - variables and self-check"
call :say "=========================================================='"
call :say "pair           : %N2%"
call :say "hidden hop     : %N1%"
call :say "pair came from : %PAIRSRC%"
call :say "service hop2   : %S2%"
call :say "service hop1   : %S1%"
call :say "config hop2    : %C2%"
call :say "config hop1    : %C1%"
call :say "client binary  : %EXE%"
call :say "guard binary   : %GUARDEXE%"
call :say "config folder  : %DATA%"
call :say "client sources : %CLIENT%"
call :say "core sources   : %CORE%"
call :say "scripts folder : %HERE%"
call :say "logs folder    : %LOGS%"
call :say "state folder   : %ProgramData%\AwgChain"
call :say "MTU            : hop1 %M1% / hop2 %M2%"
call :say ""
call :say "--- binaries and folders ---"
call :chk "%EXE%" "client binary"
call :chk "%GUARDEXE%" "guard binary"
call :chk "%BIN%\wintun.dll" "wintun.dll"
call :chk "%DATA%" "config folder"
call :chk "%CLIENT%" "client sources"
call :chk "%CORE%" "core sources"
call :chk "%CLIENT%\amd64\amneziawg.exe" "freshly built client"
call :say ""
call :say "--- helper scripts next to this file ---"
call :chk "%HERE%detect-pair.ps1" "detect-pair.ps1 (pair detection)"
call :chk "%HERE%pick-confs.ps1" "pick-confs.ps1 (up)"
call :chk "%HERE%get-endpoint.ps1" "get-endpoint.ps1 (up)"
call :chk "%HERE%make-hop1-conf.ps1" "make-hop1-conf.ps1 (up)"
call :chk "%HERE%make-hop2-conf.ps1" "make-hop2-conf.ps1 (up)"
call :chk "%HERE%mtu-probe.ps1" "mtu-probe.ps1 (mtu, verify)"
call :chk "%HERE%uapi-stats.ps1" "uapi-stats.ps1 (stats)"
call :chk "%HERE%leak-test.ps1" "leak-test.ps1 (leak)"
call :chk "%HERE%dns-lock.ps1" "dns-lock.ps1 (dns on/off)"
call :chk "%HERE%guard-up.ps1" "guard-up.ps1 (ks on/off)"
call :chk "%HERE%watchdog.ps1" "watchdog.ps1 (autoguard)"
call :say ""
call :say "--- source configs used by awgchain.bat up ---"
call :chk "%HERE%WARPv2_84.conf" "a WARP config"
call :chk "%HERE%100p.conf" "an Amnezia config"
call :say ""
call :say "--- configs the manager stores ---"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%DATA%' -File -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 200" > "%TMPTXT%" 2>&1
type "%TMPTXT%"
type "%TMPTXT%" >> "%LOG%"
call :say "--- services ---"
call :svcline "%S1%" "hop1 %N1%"
call :svcline "%S2%" "hop2 %N2%"
call :svcline "AwgChainManager" "manager"
call :say ""
call :say "--- adapters ---"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object ifIndex,InterfaceAlias,NlMtu,ConnectionState | Format-Table -AutoSize | Out-String -Width 200" > "%TMPTXT%" 2>&1
type "%TMPTXT%"
type "%TMPTXT%" >> "%LOG%"
call :say "--- go toolchain ---"
call :goenv
call :chk "%GOROOT%\bin\go.exe" "go compiler"
if exist "%TMPTXT%" del /f /q "%TMPTXT%"
call :say ""
call :say "A copy of this report is in %LOG%"
goto end

'@

if ($script:t.Contains(':cmd_vars')) {
	Ok 'the vars screen was already there'
}
else {
	$idx = $script:t.IndexOf('rem  LOGS - zip everything for the chat')
	if ($idx -lt 0) { $idx = $script:t.IndexOf("`r`n:cmd_logs`r`n") }
	if ($idx -ge 0) {
		$start = $script:t.LastIndexOf('rem =====', $idx)
		if ($start -lt 0) { $start = $idx }
		$script:t = $script:t.Substring(0, $start) + $vars + $script:t.Substring($start)
		Ok 'added the vars screen'
	}
	else {
		Bad 'could not find a place for the vars screen'
	}
}

# ------------------------------------------------- menu entry and dispatcher
if ($script:t.Contains('set "CMD=vars"')) {
	Ok 'the menu entry was already there'
}
else {
	$m = [regex]::Match($script:t, 'echo\s+33\s+patch17[^\r\n]*\r\n')
	if ($m.Success) {
		$add = 'echo.' + "`r`n" + 'echo   SELF-CHECK' + "`r`n" + 'echo    34  vars       print every variable and check every tool' + "`r`n"
		$script:t = $script:t.Insert($m.Index + $m.Length, $add)
		Ok 'added menu entry 34 (vars)'
	}
	else {
		Bad 'could not find menu entry 33 to add 34 after it'
	}

	$d = [regex]::Match($script:t, 'if "%SEL%"=="33" set "CMD=patch17"\r\n')
	if ($d.Success) {
		$script:t = $script:t.Insert($d.Index + $d.Length, 'if "%SEL%"=="34" set "CMD=vars"' + "`r`n")
		Ok 'the menu now dispatches 34 to vars'
	}
	else {
		Bad 'could not find the menu dispatcher line for 33'
	}
}

# ------------------------------------------------------------ allowed commands
if ($script:t.Contains('VALID= vars')) {
	Ok 'vars was already an allowed command'
}
else {
	if ($script:t.Contains('set "VALID= up down status')) {
		$script:t = $script:t.Replace('set "VALID= up down status', 'set "VALID= vars up down status')
		Ok 'vars is now an allowed command'
	}
	else {
		Bad 'could not find the list of allowed commands'
	}
}

# -------------------------------------------------------------------- help text
if ($script:t.Contains('awgchain.bat vars ')) {
	Ok 'the help text already mentions vars'
}
else {
	$h = [regex]::Match($script:t, 'echo   awgchain\.bat gui[^\r\n]*\r\n')
	if ($h.Success) {
		$script:t = $script:t.Insert($h.Index + $h.Length, 'echo   awgchain.bat vars              print every variable and check every tool' + "`r`n")
		Ok 'the help text now mentions vars'
	}
	else {
		Say '[note] could not find the gui line in the help text, skipping'
	}
}

# ------------------------------------------------------- no more hardcoded names
$hard = ([regex]::Matches($script:t, 'double-click hop2-amnezia')).Count
if ($hard -gt 0) {
	$script:t = $script:t.Replace('double-click hop2-amnezia', 'double-click %N2%')
	Ok ('replaced ' + $hard + ' hardcoded tunnel names in the hints')
}
else {
	Ok 'no hardcoded tunnel names left in the hints'
}

# ----------------------------------------------------------------------- write
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($Bat, $script:t, $enc)
Say ('size after : ' + $script:t.Length + ' bytes')

$check = [IO.File]::ReadAllText($Bat)
if ($check.Contains(':cmd_vars')) { Ok 'the vars screen is in the file' } else { Bad 'the vars screen is missing' }
if ($check.Contains("`r`n:chk`r`n")) { Ok 'the chk helper is in the file' } else { Bad 'the chk helper is missing' }
if ($check.Contains('detect-pair.ps1')) { Ok 'the pair detection calls detect-pair.ps1' } else { Bad 'the pair detection was not rewritten' }
if ($check.Contains('$*-hop1')) { Bad 'the broken one-liner is still in the file' } else { Ok 'the broken one-liner is gone' }

Say ''
if ($script:fails -eq 0) {
	Write-Host 'RESULT=OK'
	exit 0
}
Write-Host 'RESULT=FAIL'
exit 1
