@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title AwgChain - control panel

rem ==========================================================================
rem  AwgChain control panel - one file instead of the whole 10..27 zoo.
rem
rem  Usage:
rem     awgchain.bat                 interactive menu
rem     awgchain.bat up              raise the chain (hop1 WARP -> hop2 Amnezia)
rem     awgchain.bat down            tear the chain down
rem     awgchain.bat status          short state report
rem     awgchain.bat test            quick test: egress, path, DNS, counters
rem     awgchain.bat verify          full 3-minute quality/leak report
rem     awgchain.bat mtu             MTU probe inside the chain
rem     awgchain.bat dnson|dnsoff    DNS lock (NRPT) on/off
rem     awgchain.bat kson [sec]      kill switch on (default 180 s, 0 = hold)
rem     awgchain.bat ksoff           kill switch off
rem     awgchain.bat leak [flap]     leak test (flap = also drop hop 1)
rem     awgchain.bat build           apply + build patch 5 (kill switch)
rem     awgchain.bat build revert    remove patch 5 and rebuild
rem     awgchain.bat patch3          re-apply patch 3 and rebuild the client
rem     awgchain.bat patch4 [revert] UAPI pipe rename + UI guard, then rebuild
rem     awgchain.bat stats           handshake age and counters from the tunnels
rem     awgchain.bat install         install the freshly built client binary
rem     awgchain.bat logs            zip every log for the chat
rem
rem  Everything is logged into the logs\ subfolder next to this file.
rem  goto-only branching, no parenthesised if-blocks.
rem ==========================================================================

set "HERE=%~dp0"
set "BIN=C:\Program Files\AwgChain\bin"
set "EXE=%BIN%\awgchain.exe"
set "GUARDEXE=%BIN%\awgchain-guard.exe"
set "DATA=C:\Program Files\AwgChain\Data\Configurations"
set "CLIENT=C:\dev\vpnchain\amneziawg-windows-client"
set "CORE=C:\dev\vpnchain\amneziawg-windows"
set "LOGS=%HERE%logs"
set "TMPTXT=%TEMP%\awgchain-scratch.txt"
call :detectpair

rem tuned values from run #17; override per run:  set HOP1_MTU=1440
set "M1=1420"
set "M2=1360"
if not "%HOP1_MTU%"=="" set "M1=%HOP1_MTU%"
if not "%HOP2_MTU%"=="" set "M2=%HOP2_MTU%"

set "CMD=%~1"
set "A2=%~2"
set "A3=%~3"
if not "%CMD%"=="" goto normalize

:menu
cls
echo ==========================================================
echo   AwgChain control panel
echo   apps -^> %N2% (Amnezia) -^> %N1% (WARP) -^> ISP
echo ==========================================================
echo.
echo   CHAIN
echo     1  up        raise the chain
echo     2  down      tear it down
echo     3  status     short state report
echo.
echo   CHECKS
echo     4  test       quick test (about 1 min)
echo     5  verify     full quality + leak report (about 3 min)
echo     6  mtu        MTU probe inside the chain
echo     7  leak       kill-switch leak test
echo.
echo   PROTECTION
echo     8  dns on     lock DNS to the chain (NRPT)
echo     9  dns off    release the DNS lock
echo    10  ks on      kill switch on, self-removes in 180 s
echo    11  ks off     kill switch off
echo.
echo   BUILD / SERVICE
echo    12  build      apply + build patch 5 (kill switch)
echo    13  patch3     re-apply patch 3 and rebuild
echo    14  install    install the built client binary
echo    15  logs       zip all logs for the chat
echo    16  patch4     UAPI pipe rename + UI guard (patch 4)
echo    18  patch6     chain mode in the manager (patch 6)
echo    20  patch7     plain-text configs for chain hops (patch 7)
echo    21  dpapi      delete the encrypted copies of the configs
echo    22  patch8     one toggle in the interface runs the chain (patch 8)
echo    23  patch9     the hop carries its own pin route (patch 9)
echo    24  patch10    the chain arms its own kill switch (patch 10)
echo    25  autoguard  turn the automatic kill switch on or off
echo    26  patch11    the kill switch follows a rebuilt chain (patch 11)
echo    27  mgrlog     dump the manager journal into the logs folder
echo    28  patch12    repair the chain in seconds, not minutes (patch 12)
echo    29  patch13    build the chain from two configs in the interface
echo    30  patch14    one tunnel per chain, delete fixed (patch 14)
echo    31  patch15    edit both halves in one window (patch 15)
echo    32  patch16    off stops both hops, install unlocks (patch 16)
echo    33  patch17    show the WARP half in the editor (patch 17)
echo    35  patch18    IPv6 goes through the chain (patch 18)
echo    36  patch19    ask which config is WARP, honest MTU text (patch 19)
echo    37  ipv6on     lock IPv6 outside the chain
echo    38  ipv6off    unlock IPv6
echo    39  ipv6chk    IPv6 leak check, 6 tests
echo    40  stress     50 on/off cycles with a CSV report
echo    41  fixconfs   normalise MTU in the source configs
echo.
echo   SELF-CHECK
echo    34  vars       print every variable and check every tool
echo.
echo   LIVE NUMBERS
echo    17  stats      handshake age + counters straight from the tunnels
echo.
echo   INTERFACE
echo    19  gui        open the graphical interface (main panel after patch 8)
echo.
echo     0  exit
echo.
set "SEL="
set /p "SEL=Choose: "
set "CMD="
if "%SEL%"=="1" set "CMD=up"
if "%SEL%"=="2" set "CMD=down"
if "%SEL%"=="3" set "CMD=status"
if "%SEL%"=="4" set "CMD=test"
if "%SEL%"=="5" set "CMD=verify"
if "%SEL%"=="6" set "CMD=mtu"
if "%SEL%"=="7" set "CMD=leak"
if "%SEL%"=="8" set "CMD=dnson"
if "%SEL%"=="9" set "CMD=dnsoff"
if "%SEL%"=="10" set "CMD=kson"
if "%SEL%"=="11" set "CMD=ksoff"
if "%SEL%"=="12" set "CMD=build"
if "%SEL%"=="13" set "CMD=patch3"
if "%SEL%"=="14" set "CMD=install"
if "%SEL%"=="15" set "CMD=logs"
if "%SEL%"=="16" set "CMD=patch4"
if "%SEL%"=="17" set "CMD=stats"
if "%SEL%"=="18" set "CMD=patch6"
if "%SEL%"=="19" set "CMD=gui"
if "%SEL%"=="20" set "CMD=patch7"
if "%SEL%"=="21" set "CMD=dpapi"
if "%SEL%"=="22" set "CMD=patch8"
if "%SEL%"=="23" set "CMD=patch9"
if "%SEL%"=="24" set "CMD=patch10"
if "%SEL%"=="25" set "CMD=autoguard"
if "%SEL%"=="26" set "CMD=patch11"
if "%SEL%"=="27" set "CMD=mgrlog"
if "%SEL%"=="28" set "CMD=patch12"
if "%SEL%"=="29" set "CMD=patch13"
if "%SEL%"=="30" set "CMD=patch14"
if "%SEL%"=="31" set "CMD=patch15"
if "%SEL%"=="32" set "CMD=patch16"
if "%SEL%"=="33" set "CMD=patch17"
if "%SEL%"=="35" set "CMD=patch18"
if "%SEL%"=="36" set "CMD=patch19"
if "%SEL%"=="37" set "CMD=ipv6on"
if "%SEL%"=="38" set "CMD=ipv6off"
if "%SEL%"=="39" set "CMD=ipv6chk"
if "%SEL%"=="40" set "CMD=stress"
if "%SEL%"=="41" set "CMD=fixconfs"
if "%SEL%"=="34" set "CMD=vars"
if "%SEL%"=="0" goto quit
if not defined CMD goto menu
set "MENUMODE=1"

:normalize
if /i "%CMD%"=="dns" goto dnsalias
if /i "%CMD%"=="ks" goto ksalias
if /i "%CMD%"=="killswitch" goto ksalias
if /i "%CMD%"=="-h" set "CMD=help"
if /i "%CMD%"=="/?" set "CMD=help"
if /i "%CMD%"=="--help" set "CMD=help"
goto validate

:dnsalias
set "CMD=dnson"
if /i "%A2%"=="off" set "CMD=dnsoff"
set "A2="
goto validate

:ksalias
set "CMD=kson"
if /i "%A2%"=="off" set "CMD=ksoff"
if /i "%A2%"=="on" set "A2=%A3%"
goto validate

:validate
set "VALID= vars up down status stats test verify mtu leak dnson dnsoff kson ksoff build patch3 patch4 patch6 patch7 patch8 patch9 patch10 patch11 patch12 patch13 patch14 patch15 patch16 patch17 patch18 patch19 patch20 patch22 applog srcdump ksstop ipv6on ipv6off ipv6chk stress fixconfs autoguard mgrlog dpapi install gui logs help "
echo %VALID%| findstr /i /c:" %CMD% " >nul
if errorlevel 1 goto badcmd
if /i "%CMD%"=="help" goto cmd_help

net session >nul 2>&1
if errorlevel 1 goto elevate
goto dispatch

:elevate
set "PASS=%CMD%"
if not "%A2%"=="" set "PASS=%CMD% %A2%"
echo Requesting administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%PASS%' -Verb RunAs"
exit /b 0

:dispatch
if not exist "%LOGS%" mkdir "%LOGS%"
goto cmd_%CMD%

:badcmd
echo Unknown command "%CMD%".
goto cmd_help

:cmd_help
echo.
echo AwgChain control panel
echo.
echo   awgchain.bat                  interactive menu
echo   awgchain.bat up ^| down ^| status
echo   awgchain.bat test ^| verify ^| mtu ^| leak [flap]
echo   awgchain.bat dns on ^| dns off
echo   awgchain.bat ks on [seconds] ^| ks off
echo   awgchain.bat build [revert] ^| patch3 ^| install ^| logs
echo   awgchain.bat patch4 [revert]   UAPI pipe rename + UI guard
echo   awgchain.bat stats             handshake age + counters (UAPI)
echo   awgchain.bat patch6 [revert]   chain mode in the manager
echo   awgchain.bat patch7 [revert]   plain-text configs for chain hops
echo   awgchain.bat patch8 [revert]   the manager keeps the hops in order
echo   awgchain.bat patch9 [revert]   each hop lays its own pin route
echo   awgchain.bat patch10 [revert]  the chain arms its own kill switch
echo   awgchain.bat autoguard on^|off^|status
echo   awgchain.bat patch11 [revert]  the kill switch follows a rebuilt chain
echo   awgchain.bat mgrlog            dump the manager journal to the logs folder
echo   awgchain.bat patch12 [revert]  a repair that takes seconds
echo   awgchain.bat patch13 [revert]  build the chain from two configs
echo   awgchain.bat patch14 [revert]  one tunnel per chain, delete fixed
echo   awgchain.bat patch15 [revert]  edit both halves in one window
echo   awgchain.bat patch16 [revert]  turning the chain off stops both hops
echo   awgchain.bat patch17 [revert]  show the WARP half in the editor
echo   awgchain.bat dpapi             delete the encrypted copies of the configs
echo   awgchain.bat gui               open the graphical interface
echo   awgchain.bat vars              print every variable and check every tool
echo.
echo All logs go to: %LOGS%
goto end

rem ==========================================================================
rem  UP - raise the chain
rem ==========================================================================
:cmd_up
set "LOG=%LOGS%\chain-log.txt"
if not exist "%EXE%" goto nobin
if not exist "%DATA%" mkdir "%DATA%"
if exist "%DATA%\%N1%.conf.dpapi" echo   note: a DPAPI copy of hop 1 exists, apply patch 7 to stop the manager eating the plain file

set "SRC1="
set "SRC2="
for /f "usebackq tokens=1,* delims==" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%pick-confs.ps1" -Folder "%HERE%."`) do call :setvar "%%A" "%%B"
if not defined SRC1 goto noconf
if not defined SRC2 goto noconf
if not exist "%SRC1%" goto noconf
if not exist "%SRC2%" goto noconf

echo ==========================================================
echo  Raising the chain: apps -^> hop2 -^> hop1 -^> ISP
echo ==========================================================
echo hop 1 (WARP)    : %SRC1%
echo hop 2 (Amnezia) : %SRC2%
echo MTU             : hop1 %M1% / hop2 %M2%
echo pair            : %N2%   hidden hop: %N1%
echo.

echo ==== %DATE% %TIME% chain-up ====> "%LOG%"

echo === removing any previous chain services ===
call :drop "%S2%"
call :drop "%S1%"

set "EP2="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%get-endpoint.ps1" -Source "%SRC2%"`) do set "EP2=%%I"
if not defined EP2 goto noendpoint
echo hop 2 endpoint  : %EP2%
echo hop 2 endpoint : %EP2%>> "%LOG%"
echo %EP2%| findstr /R "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if errorlevel 1 goto hostname

echo === building %C1% (Table = off, MTU %M1%, pinned to the physical NIC) ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%make-hop1-conf.ps1" -Source "%SRC1%" -Out "%C1%" -Mtu %M1%
if errorlevel 1 goto conf1fail
if not exist "%C1%" goto conf1fail

echo === building %C2% (pinned to %N1%, MTU %M2%, routes on) ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%make-hop2-conf.ps1" -Source "%SRC2%" -Out "%C2%" -PinVia "%N1%" -Mtu %M2%
if errorlevel 1 goto conf2fail
if not exist "%C2%" goto conf2fail

echo --- hop1 config, private key hidden --->> "%LOG%"
findstr /V /C:"PrivateKey" "%C1%" >> "%LOG%" 2>&1
echo --- hop2 config, private key hidden --->> "%LOG%"
findstr /V /C:"PrivateKey" "%C2%" >> "%LOG%" 2>&1
echo --- egress BEFORE --->> "%LOG%"
curl -s --max-time 10 https://api.ipify.org >> "%LOG%" 2>&1
echo.>> "%LOG%"

echo === starting hop 1 ===
echo --- sc create hop1 --->> "%LOG%"
sc create "%S1%" binPath= "\"%EXE%\" /tunnelservice \"%C1%\"" start= demand depend= Nsi/TcpIp DisplayName= "AwgChain Tunnel: %N1%" >> "%LOG%" 2>&1
if errorlevel 1 goto screate1
sc sidtype "%S1%" unrestricted >> "%LOG%" 2>&1
sc start "%S1%" >> "%LOG%" 2>&1
timeout /t 10 /nobreak >nul

set "IF1="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "(Get-NetAdapter -Name '%N1%' -ErrorAction SilentlyContinue).ifIndex"`) do set "IF1=%%I"
if not defined IF1 goto nohop1
echo hop 1 adapter   : ifIndex !IF1!
echo hop1 ifIndex : !IF1!>> "%LOG%"

echo === pinning route %EP2%/32 via ifIndex !IF1! ===
echo --- route add --->> "%LOG%"
route add %EP2% mask 255.255.255.255 0.0.0.0 if !IF1! metric 1 >> "%LOG%" 2>&1

echo === starting hop 2 ===
echo --- sc create hop2 --->> "%LOG%"
sc create "%S2%" binPath= "\"%EXE%\" /tunnelservice \"%C2%\"" start= demand depend= Nsi/TcpIp DisplayName= "AwgChain Tunnel: %N2%" >> "%LOG%" 2>&1
if errorlevel 1 goto screate2
sc sidtype "%S2%" unrestricted >> "%LOG%" 2>&1
sc start "%S2%" >> "%LOG%" 2>&1
timeout /t 12 /nobreak >nul

echo === collecting diagnostics ===
call :snapshot
echo --- egress AFTER, expect the Amnezia server address --->> "%LOG%"
curl -s --max-time 20 https://api.ipify.org >> "%LOG%" 2>&1
echo.>> "%LOG%"
echo --- tunnel log --->> "%LOG%"
"%EXE%" /dumplog >> "%LOG%" 2>&1

echo.
call :egress
echo.
echo ==========================================================
echo  Chain is up. Next, if you want the full protection:
echo     awgchain.bat dnson      lock DNS to the chain
echo     awgchain.bat kson 180   kill switch for 3 minutes
echo  Checks:  awgchain.bat test  /  verify  /  leak
echo  Log: %LOG%
echo ==========================================================
goto end

rem ==========================================================================
rem  DOWN - tear the chain down
rem ==========================================================================
:cmd_down
set "LOG=%LOGS%\chain-down-log.txt"
echo ==== %DATE% %TIME% chain-down ====> "%LOG%"
echo === stopping the kill switch first, if it is running ===
if exist "%GUARDEXE%" "%GUARDEXE%" -stop >> "%LOG%" 2>&1
taskkill /f /im awgchain-guard.exe >nul 2>&1

set "EP2="
if not exist "%C2%" goto noep
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%get-endpoint.ps1" -Source "%C2%"`) do set "EP2=%%I"
:noep

call :kill "%S2%"
if not defined EP2 goto noroute
echo === removing the pinned route %EP2%/32 ===
route delete %EP2% >> "%LOG%" 2>&1
:noroute
call :kill "%S1%"
call :kill "AwgChainManager"

echo --- remaining chain services, expect none --->> "%LOG%"
sc query type= service state= all 2>nul | findstr /I "AwgChain" >> "%LOG%" 2>&1
if errorlevel 1 echo none>> "%LOG%"
echo --- adapters after --->> "%LOG%"
powershell -NoProfile -Command "Get-NetAdapter | Select-Object ifIndex,Name,Status | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
echo --- default routes after --->> "%LOG%"
powershell -NoProfile -Command "Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0','0.0.0.0/1','128.0.0.0/1') } | Select-Object ifIndex,InterfaceAlias,DestinationPrefix,NextHop,RouteMetric | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
echo --- egress after, expect your ISP address --->> "%LOG%"
curl -s --max-time 10 https://api.ipify.org >> "%LOG%" 2>&1
echo.>> "%LOG%"

echo.
echo Chain removed. If the DNS lock is still on: awgchain.bat dnsoff
call :egress
goto end

rem ==========================================================================
rem  STATUS - short state report
rem ==========================================================================
:cmd_status
set "LOG=%LOGS%\status-log.txt"
echo ==== %DATE% %TIME% status ====> "%LOG%"
echo pair: %N2%  hidden hop: %N1%>> "%LOG%"
echo ==========================================================
echo  AwgChain status - pair: %N2%  hidden hop: %N1%
echo ==========================================================
echo.
echo --- services ---
call :svcline "%S1%" "hop1 %N1%"
call :svcline "%S2%" "hop2 %N2%"
echo.
echo --- adapters and MTU ---
powershell -NoProfile -Command "Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -in @('%N1%','%N2%','Ethernet') } | Select-Object ifIndex,InterfaceAlias,NlMtu,ConnectionState | Format-Table -AutoSize | Out-String -Width 200"
echo --- kill switch ---
powershell -NoProfile -Command "$p = Get-Process -Name 'awgchain-guard' -ErrorAction SilentlyContinue; if ($p) { 'guard RUNNING pid=' + $p.Id } else { 'guard not running' }"
echo --- DNS lock (NRPT) ---
powershell -NoProfile -Command "$r = Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Comment -like '*AwgChain*' }; if ($r) { 'NRPT rules: ' + $r.Count } else { 'no AwgChain NRPT rule' }"
echo --- DNS servers ---
powershell -NoProfile -Command "Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses } | Select-Object InterfaceAlias,ServerAddresses | Format-Table -AutoSize | Out-String -Width 200"
echo --- default routes ---
powershell -NoProfile -Command "Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0','0.0.0.0/1','128.0.0.0/1') } | Select-Object ifIndex,InterfaceAlias,DestinationPrefix,NextHop,RouteMetric | Format-Table -AutoSize | Out-String -Width 200"
echo --- binaries ---
if exist "%EXE%" for %%F in ("%EXE%") do echo awgchain.exe       %%~zF bytes
if not exist "%EXE%" echo awgchain.exe       MISSING
if exist "%GUARDEXE%" for %%F in ("%GUARDEXE%") do echo awgchain-guard.exe %%~zF bytes
if not exist "%GUARDEXE%" echo awgchain-guard.exe MISSING (awgchain.bat build)
echo.
call :egress
echo.
echo --- same report saved ---
call :snapshot
echo %LOG%
goto end

rem ==========================================================================
rem  TEST - quick functional test
rem ==========================================================================
:cmd_test
set "LOG=%LOGS%\chain-test-log.txt"
echo ==== %DATE% %TIME% chain-test ====> "%LOG%"
echo === 1/6 adapters ===
powershell -NoProfile -Command "Get-NetAdapter | Select-Object ifIndex,Name,Status | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
echo === 2/6 egress identity ===
echo --- egress --->> "%LOG%"
curl -s --max-time 20 https://api.ipify.org >> "%LOG%" 2>&1
echo.>> "%LOG%"
curl -s --max-time 20 http://ip-api.com/json >> "%LOG%" 2>&1
echo.>> "%LOG%"
echo --- cloudflare trace, warp must be off --->> "%LOG%"
curl -s --max-time 20 https://www.cloudflare.com/cdn-cgi/trace >> "%LOG%" 2>&1
echo.>> "%LOG%"
echo === 3/6 path out ===
tracert -d -h 8 -w 800 1.1.1.1 >> "%LOG%" 2>&1
echo === 4/6 payload probe ===
call :probe 1372
call :probe 1332
call :probe 1272
call :probe 1200
echo === 5/6 DNS ===
powershell -NoProfile -Command "Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object ifIndex,InterfaceAlias,ServerAddresses | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
nslookup example.com >> "%LOG%" 2>&1
powershell -NoProfile -Command "Get-DnsClientNrptPolicy -ErrorAction SilentlyContinue | Select-Object Namespace,NameServers | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
echo === 6/6 counters and leaks ===
call :counters
echo --- ipv6 egress, empty is good --->> "%LOG%"
curl -s -6 --max-time 8 https://api64.ipify.org >> "%LOG%" 2>&1
echo.>> "%LOG%"
call :snapshot
type "%LOG%"
echo.
echo Log: %LOG%
goto end

rem ==========================================================================
rem  VERIFY - full quality report
rem ==========================================================================
:cmd_verify
set "LOG=%LOGS%\chain-verify-log.txt"
powershell -NoProfile -Command "if ((Get-NetAdapter -Name '%N2%' -ErrorAction SilentlyContinue).Status -eq 'Up') { exit 0 } else { exit 1 }"
if errorlevel 1 goto nochain
echo ==========================================================
echo  Verifying the chain: MTU, speed, stability, leaks
echo  Takes about three minutes, leave this window open.
echo ==========================================================
echo ==== %DATE% %TIME% chain-verify ====> "%LOG%"

echo === 1/6 interface state ===
powershell -NoProfile -Command "Get-NetIPInterface -AddressFamily IPv4 | Select-Object ifIndex,InterfaceAlias,NlMtu,ConnectionState | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
powershell -NoProfile -Command "Get-NetIPInterface -AddressFamily IPv6 | Select-Object ifIndex,InterfaceAlias,NlMtu,ConnectionState | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
set "MTU2="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "(Get-NetIPInterface -InterfaceAlias '%N2%' -AddressFamily IPv4).NlMtu"`) do set "MTU2=%%I"
if not defined MTU2 set "MTU2=%M2%"
echo hop 2 MTU : !MTU2!
echo hop2 configured MTU : !MTU2!>> "%LOG%"

echo === 2/6 MTU probe through the chain ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%mtu-probe.ps1" -Target 1.1.1.1 -Label "through the chain" -Low 1000 -High 1472 >> "%LOG%" 2>&1
echo expectation: max payload = hop2 MTU minus 28>> "%LOG%"

echo === 3/6 download speed, 10 MB ===
curl -s -o NUL --max-time 120 -w "bytes=%%{size_download} seconds=%%{time_total} bytes_per_sec=%%{speed_download}\n" https://speed.cloudflare.com/__down?bytes=10000000 >> "%LOG%" 2>&1
ping -n 6 1.1.1.1 >> "%LOG%" 2>&1

echo === 4/6 stability, three samples 40 s apart ===
call :sample 1
timeout /t 40 /nobreak >nul
call :sample 2
timeout /t 40 /nobreak >nul
call :sample 3

echo === 5/6 leak checks ===
echo --- egress v4 --->> "%LOG%"
curl -s --max-time 15 https://api.ipify.org >> "%LOG%" 2>&1
echo.>> "%LOG%"
echo --- egress v6, empty is good --->> "%LOG%"
curl -s --max-time 10 -6 https://api64.ipify.org >> "%LOG%" 2>&1
echo.>> "%LOG%"
echo --- which resolver answered --->> "%LOG%"
powershell -NoProfile -Command "try { (Resolve-DnsName -Name whoami.akamai.net -Type A -ErrorAction Stop).IPAddress } catch { 'resolve failed' }" >> "%LOG%" 2>&1
nslookup example.com >> "%LOG%" 2>&1
call :snapshot

echo === 6/6 proving hop 2 rides inside hop 1 ===
tracert -d -h 6 -w 1500 1.1.1.1 >> "%LOG%" 2>&1
powershell -NoProfile -Command "Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -like '*/32' -and $_.InterfaceAlias -eq '%N1%' } | Select-Object ifIndex,InterfaceAlias,DestinationPrefix,RouteMetric | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1

type "%LOG%"
echo.
echo Done. Send %LOG%  (or run: awgchain.bat logs)
goto end

rem ==========================================================================
rem  MTU - probe only
rem ==========================================================================
:cmd_mtu
set "LOG=%LOGS%\mtu-probe-log.txt"
echo ==== %DATE% %TIME% mtu probe ====> "%LOG%"
echo === probing inside the chain (only this number is trustworthy) ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%mtu-probe.ps1" -Target 1.1.1.1 -Label "through the chain" -Low 1000 -High 1472 >> "%LOG%" 2>&1
powershell -NoProfile -Command "Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -in @('%N1%','%N2%','Ethernet') } | Select-Object InterfaceAlias,NlMtu | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
echo current settings: hop1 %M1% / hop2 %M2%>> "%LOG%"
type "%LOG%"
echo.
echo Rule of thumb: max payload = hop2 MTU - 28. Change MTU like this:
echo     set HOP1_MTU=1420 ^&^& set HOP2_MTU=1360 ^&^& awgchain.bat up
goto end

rem ==========================================================================
rem  DNS LOCK on/off
rem ==========================================================================
:cmd_dnson
set "LOG=%LOGS%\dns-lock-log.txt"
if not exist "%HERE%dns-lock.ps1" goto nodnsps
echo ==== %DATE% %TIME% dns lock on ====> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%dns-lock.ps1" -Tunnel "%N2%" -Hop1 "%N1%" >> "%LOG%" 2>&1
ipconfig /flushdns >> "%LOG%" 2>&1
type "%LOG%"
echo.
echo Release it again with: awgchain.bat dnsoff
goto end

:cmd_dnsoff
set "LOG=%LOGS%\dns-unlock-log.txt"
if not exist "%HERE%dns-lock.ps1" goto nodnsps
echo ==== %DATE% %TIME% dns lock off ====> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%dns-lock.ps1" -Remove >> "%LOG%" 2>&1
ipconfig /flushdns >> "%LOG%" 2>&1
type "%LOG%"
goto end

rem ==========================================================================
rem  KILL SWITCH on/off
rem ==========================================================================
:cmd_kson
set "LOG=%LOGS%\killswitch-on-log.txt"
set "SEC=%A2%"
if "%SEC%"=="" set "SEC=180"
set "NOLAN="
if /i "%A3%"=="/nolan" set "NOLAN=-NoLan"
if /i "%A3%"=="nolan" set "NOLAN=-NoLan"
if not exist "%GUARDEXE%" goto noguard
if not exist "%HERE%guard-up.ps1" goto noguardps
echo ==================================================> "%LOG%"
echo AwgChain kill switch ON >> "%LOG%"
echo date: %DATE% %TIME% >> "%LOG%"
echo timeout: %SEC% seconds >> "%LOG%"
echo ==================================================>> "%LOG%"
echo.
echo Starting the kill switch, hold time %SEC% s (0 = until switched off).
echo Everything outside the chain gets blocked. If you lose the network,
echo wait for the timeout or run:  awgchain.bat ksoff
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%guard-up.ps1" -Timeout %SEC% -LogDir "%LOGS%" %NOLAN% >> "%LOG%" 2>&1
type "%LOG%"
echo.
echo Next: awgchain.bat leak   then   awgchain.bat verify
goto end

:cmd_ksoff
set "LOG=%LOGS%\killswitch-off-log.txt"
echo ==== %DATE% %TIME% kill switch off ====> "%LOG%"
if not exist "%GUARDEXE%" goto noguard
"%GUARDEXE%" -stop >> "%LOG%" 2>&1
timeout /t 3 /nobreak >nul
powershell -NoProfile -Command "$p = Get-Process -Name 'awgchain-guard' -ErrorAction SilentlyContinue; if ($p) { exit 1 } else { exit 0 }"
if not errorlevel 1 goto ksgone
echo guard still running, killing it>> "%LOG%"
taskkill /f /im awgchain-guard.exe >> "%LOG%" 2>&1
timeout /t 2 /nobreak >nul
:ksgone
echo RESULT=OK>> "%LOG%"
if exist "%LOGS%\guard-log.txt" echo --- guard log tail --->> "%LOG%"
if exist "%LOGS%\guard-log.txt" powershell -NoProfile -Command "Get-Content -LiteralPath '%LOGS%\guard-log.txt' -Tail 20" >> "%LOG%" 2>&1
type "%LOG%"
echo.
call :egress
goto end

rem ==========================================================================
rem  LEAK TEST
rem ==========================================================================
:cmd_leak
set "LOG=%LOGS%\leak-test-log.txt"
if not exist "%HERE%leak-test.ps1" goto noleakps
set "FLAP="
if /i "%A2%"=="flap" set "FLAP=-Flap"
if /i "%A2%"=="/flap" set "FLAP=-Flap"
echo ==== %DATE% %TIME% leak test %A2% ====> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%leak-test.ps1" %FLAP% >> "%LOG%" 2>&1
call :snapshot
type "%LOG%"
echo.
echo Log: %LOG%
goto end

rem ==========================================================================
rem  BUILD - patch 5 apply/revert + build
rem ==========================================================================
:cmd_build
set "LOG=%LOGS%\patch5-log.txt"
set "MODE=apply"
if /i "%A2%"=="revert" set "MODE=revert"
if /i "%A2%"=="/revert" set "MODE=revert"
echo ==================================================> "%LOG%"
echo AwgChain patch 5 - %MODE% >> "%LOG%"
echo date: %DATE% %TIME% >> "%LOG%"
echo ==================================================>> "%LOG%"
if not exist "%CORE%\tunnel\firewall\rules.go" goto nocore
if not exist "%CLIENT%\go.mod" goto noclient
if /i "%MODE%"=="revert" goto b_revert
if not exist "%HERE%chainfirewall.go" goto nosrc
if not exist "%HERE%guard-main.go" goto nosrc
echo [1/4] copying the patch 5 sources...
echo --- copy sources --->> "%LOG%"
copy /y "%HERE%chainfirewall.go" "%CORE%\tunnel\firewall\chainfirewall.go" >> "%LOG%" 2>&1
if errorlevel 1 goto copyfail
if not exist "%CLIENT%\chainguard" mkdir "%CLIENT%\chainguard"
copy /y "%HERE%guard-main.go" "%CLIENT%\chainguard\main.go" >> "%LOG%" 2>&1
if errorlevel 1 goto copyfail
goto b_build

:b_revert
echo [1/4] removing the patch 5 sources...
if exist "%CORE%\tunnel\firewall\chainfirewall.go" del /f /q "%CORE%\tunnel\firewall\chainfirewall.go" >> "%LOG%" 2>&1
if exist "%CLIENT%\chainguard\main.go" del /f /q "%CLIENT%\chainguard\main.go" >> "%LOG%" 2>&1
if exist "%CLIENT%\chainguard" rmdir /q "%CLIENT%\chainguard" >> "%LOG%" 2>&1
if exist "%GUARDEXE%" del /f /q "%GUARDEXE%" >> "%LOG%" 2>&1
goto b_build

:b_build
echo [2/4] preparing the build environment...
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
cd /d "%CLIENT%"
go version >> "%LOG%" 2>&1
echo [3/4] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
if /i "%MODE%"=="revert" goto b_reverted
echo     stopping the running guard so its file can be replaced...
taskkill /F /IM awgchain-guard.exe >nul 2>&1
ping -n 3 127.0.0.1 >nul
echo [4/4] building awgchain-guard.exe...
echo --- go build guard --->> "%LOG%"
go build -ldflags "-s -w" -trimpath -buildvcs=false -o amd64\awgchain-guard.exe .\chainguard >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
if not exist "%BIN%" mkdir "%BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%copy-guard.ps1" -Src "%CLIENT%\amd64\awgchain-guard.exe" -Dst "%GUARDEXE%" >> "%LOG%" 2>&1
if errorlevel 1 goto copyfail
for %%F in ("%GUARDEXE%") do echo guard size: %%~zF >> "%LOG%"
echo RESULT=OK>> "%LOG%"
echo.
echo [OK] Patch 5 built. Guard: %GUARDEXE%
echo      The running awgchain.exe was not replaced, the chain can stay up.
echo      Next: awgchain.bat kson 180
goto end

:b_reverted
echo RESULT=REVERTED>> "%LOG%"
echo [OK] Patch 5 removed, the tree builds again without it.
goto end

rem ==========================================================================
rem  PATCH3 - re-apply patch 3 and rebuild
rem ==========================================================================
:cmd_patch3
set "LOG=%LOGS%\patch3-log.txt"
if not exist "%HERE%apply-patch3.ps1" goto nopatch3ps
echo ==== %DATE% %TIME% patch3 %A2% ====> "%LOG%"
set "P3ARG="
if /i "%A2%"=="revert" set "P3ARG=-Revert"
if /i "%A2%"=="/revert" set "P3ARG=-Revert"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%apply-patch3.ps1" -Core "%CORE%" %P3ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch3fail
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
cd /d "%CLIENT%"
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo RESULT=OK>> "%LOG%"
echo [OK] Patch 3 handled and the client rebuilt.
echo      Install it with: awgchain.bat install   (chain must be down)
goto end

rem ==========================================================================
rem  STATS - handshake age and counters straight from the tunnels (UAPI)
rem ==========================================================================
:cmd_stats
set "LOG=%LOGS%\stats-log.txt"
if not exist "%HERE%uapi-stats.ps1" goto nostatsps
echo ==== %DATE% %TIME% stats ====> "%LOG%"
echo ==========================================================
echo  AwgChain live numbers, read from the tunnels themselves
echo ==========================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%uapi-stats.ps1" -All -Hop1 "%N1%" -Hop2 "%N2%" %A2% >> "%LOG%" 2>&1
type "%LOG%"
echo.
echo  ALIVE means the hop handshook less than 180 seconds ago.
echo  A live chain rekeys about every 2 minutes, so anything older is dead.
echo.
echo  Saved to: %LOG%
goto end

rem ==========================================================================
rem  PATCH6 - chain mode in the manager, then rebuild
rem ==========================================================================
:cmd_patch6
set "LOG=%LOGS%\patch6-log.txt"
if not exist "%HERE%patch6.ps1" goto nopatch6ps
if not exist "%HERE%chainmanager.go" goto nopatch6src
if not exist "%HERE%chainui.go" goto nopatch6src
echo ==== %DATE% %TIME% patch6 %A2% ====> "%LOG%"
set "P6ARG="
if /i "%A2%"=="revert" set "P6ARG=-Revert"
if /i "%A2%"=="/revert" set "P6ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/3] patching the sources...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch6.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P6ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch6fail
cd /d "%CLIENT%"
echo [2/3] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo [3/3] building awgchain-guard.exe...
if not exist "%CLIENT%\chainguard\main.go" goto p6_noguard
echo --- go build guard --->> "%LOG%"
go build -ldflags "-s -w" -trimpath -buildvcs=false -o amd64\awgchain-guard.exe .\chainguard >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
if not exist "%BIN%" mkdir "%BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%copy-guard.ps1" -Src "%CLIENT%\amd64\awgchain-guard.exe" -Dst "%GUARDEXE%" >> "%LOG%" 2>&1
for %%F in ("%GUARDEXE%") do echo guard size: %%~zF >> "%LOG%"
:p6_noguard
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 6 applied and everything rebuilt.
echo       Next, to put the new binary in place:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat up
goto end

rem ==========================================================================
rem  PATCH7 - plain-text configs for chain hops, then rebuild
rem ==========================================================================
:cmd_patch7
set "LOG=%LOGS%\patch7-log.txt"
if not exist "%HERE%patch7.ps1" goto nopatch7ps
if not exist "%HERE%chainconf.go" goto nopatch7src
echo ==== %DATE% %TIME% patch7 %A2% ====> "%LOG%"
set "P7ARG="
if /i "%A2%"=="revert" set "P7ARG=-Revert"
if /i "%A2%"=="/revert" set "P7ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/3] patching the core sources...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch7.ps1" -Core "%CORE%" -Here "%HERE0%" %P7ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch7fail
cd /d "%CLIENT%"
echo [2/3] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo [3/3] building awgchain-guard.exe...
if not exist "%CLIENT%\chainguard\main.go" goto p7_noguard
echo --- go build guard --->> "%LOG%"
go build -ldflags "-s -w" -trimpath -buildvcs=false -o amd64\awgchain-guard.exe .\chainguard >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
if not exist "%BIN%" mkdir "%BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%copy-guard.ps1" -Src "%CLIENT%\amd64\awgchain-guard.exe" -Dst "%GUARDEXE%" >> "%LOG%" 2>&1
for %%F in ("%GUARDEXE%") do echo guard size: %%~zF >> "%LOG%"
:p7_noguard
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 7 applied and everything rebuilt.
echo       Next, to put the new binary in place:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat up
goto end

rem ==========================================================================
rem  PATCH12 - a repair that takes seconds instead of minutes
rem ==========================================================================
rem ==========================================================================
rem  PATCH17 - the editor shows the WARP half again
rem ==========================================================================
:cmd_patch17
set "LOG=%LOGS%\patch17-log.txt"
if not exist "%HERE%patch17.ps1" goto nopatch17ps
if not exist "%HERE%chainbuild-ui.go" goto nopatch17src
echo ==== %DATE% %TIME% patch17 %A2% ====> "%LOG%"
set "P17ARG="
if /i "%A2%"=="revert" set "P17ARG=-Revert"
if /i "%A2%"=="/revert" set "P17ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/2] patching the editor window...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch17.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P17ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch17fail
cd /d "%CLIENT%"
echo [2/2] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 17 applied and the client rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui
goto end

rem ==========================================================================
rem  PATCH16 - off stops both hops, install unlocks the binary
rem ==========================================================================
:cmd_patch16
set "LOG=%LOGS%\patch16-log.txt"
if not exist "%HERE%patch16.ps1" goto nopatch16ps
if not exist "%HERE%chainorder.go" goto nopatch16src
echo ==== %DATE% %TIME% patch16 %A2% ====> "%LOG%"
set "P16ARG="
if /i "%A2%"=="revert" set "P16ARG=-Revert"
if /i "%A2%"=="/revert" set "P16ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/2] patching the manager...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch16.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P16ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch16fail
cd /d "%CLIENT%"
echo [2/2] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 16 applied and the client rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui
goto end

rem ==========================================================================
rem  PATCH15 - both halves of the chain in one editor window
rem ==========================================================================
:cmd_patch15
set "LOG=%LOGS%\patch15-log.txt"
if not exist "%HERE%patch15.ps1" goto nopatch15ps
if not exist "%HERE%chainbuild-ui.go" goto nopatch15src
echo ==== %DATE% %TIME% patch15 %A2% ====> "%LOG%"
set "P15ARG="
if /i "%A2%"=="revert" set "P15ARG=-Revert"
if /i "%A2%"=="/revert" set "P15ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/2] patching the editor window and the highlighter...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch15.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P15ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch15fail
cd /d "%CLIENT%"
echo [2/2] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 15 applied and the client rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui
goto end

rem ==========================================================================
rem  PATCH14 - the chain shows up as a single tunnel
rem ==========================================================================
:cmd_patch14
set "LOG=%LOGS%\patch14-log.txt"
if not exist "%HERE%patch14.ps1" goto nopatch14ps
if not exist "%HERE%chainbuild-conf.go" goto nopatch14src
if not exist "%HERE%chainbuild-ui.go" goto nopatch14src
echo ==== %DATE% %TIME% patch14 %A2% ====> "%LOG%"
set "P14ARG="
if /i "%A2%"=="revert" set "P14ARG=-Revert"
if /i "%A2%"=="/revert" set "P14ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/2] patching the interface, the list and the config store...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch14.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P14ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch14fail
cd /d "%CLIENT%"
echo [2/2] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 14 applied and the client rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui
goto end

rem ==========================================================================
rem  PATCH13 - two plain configs become a chain, from the interface
rem ==========================================================================
:cmd_patch13
set "LOG=%LOGS%\patch13-log.txt"
if not exist "%HERE%patch13.ps1" goto nopatch13ps
if not exist "%HERE%chainbuild-conf.go" goto nopatch13src
if not exist "%HERE%chainbuild-ui.go" goto nopatch13src
echo ==== %DATE% %TIME% patch13 %A2% ====> "%LOG%"
set "P13ARG="
if /i "%A2%"=="revert" set "P13ARG=-Revert"
if /i "%A2%"=="/revert" set "P13ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/2] patching the interface and the config writer...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch13.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P13ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch13fail
cd /d "%CLIENT%"
echo [2/2] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 13 applied and the client rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui
echo       then in the interface: Add Tunnel -^> Build a chain from two configs...
goto end

:cmd_patch12
set "LOG=%LOGS%\patch12-log.txt"
if not exist "%HERE%patch12.ps1" goto nopatch12ps
if not exist "%HERE%chainguard.go" goto nopatch12src
echo ==== %DATE% %TIME% patch12 %A2% ====> "%LOG%"
set "P12ARG="
if /i "%A2%"=="revert" set "P12ARG=-Revert"
if /i "%A2%"=="/revert" set "P12ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/2] patching the manager watch...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch12.ps1" -Client "%CLIENT%" -Here "%HERE0%" %P12ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch12fail
cd /d "%CLIENT%"
echo [2/2] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 12 applied and the client rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui     then double-click %N2%
goto end

rem ==========================================================================
rem  PATCH11 - the kill switch follows the chain when it is rebuilt
rem ==========================================================================
:cmd_patch11
set "LOG=%LOGS%\patch11-log.txt"
if not exist "%HERE%patch11.ps1" goto nopatch11ps
if not exist "%HERE%guard-main.go" goto nopatch11src
if not exist "%HERE%chainguard.go" goto nopatch11src
echo ==== %DATE% %TIME% patch11 %A2% ====> "%LOG%"
set "P11ARG="
if /i "%A2%"=="revert" set "P11ARG=-Revert"
if /i "%A2%"=="/revert" set "P11ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/3] patching the guard and the manager watch...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch11.ps1" -Client "%CLIENT%" -Here "%HERE0%" %P11ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch11fail
cd /d "%CLIENT%"
echo [2/3] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo [3/3] building awgchain-guard.exe...
if not exist "%CLIENT%\chainguard\main.go" goto p11_noguard
echo --- go build guard --->> "%LOG%"
go build -ldflags "-s -w" -trimpath -buildvcs=false -o amd64\awgchain-guard.exe .\chainguard >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
if not exist "%BIN%" mkdir "%BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%copy-guard.ps1" -Src "%CLIENT%\amd64\awgchain-guard.exe" -Dst "%GUARDEXE%" >> "%LOG%" 2>&1
for %%F in ("%GUARDEXE%") do echo guard size: %%~zF >> "%LOG%"
:p11_noguard
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 11 applied and everything rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui     then double-click %N2%
goto end

rem ==========================================================================
rem  MGRLOG - the manager journal, where the chain writes what it is doing
rem ==========================================================================
:cmd_mgrlog
set "LOG=%LOGS%\manager-log.txt"
if not exist "%LOGS%" mkdir "%LOGS%"
if not exist "%EXE%" goto nobin
"%EXE%" /dumplog > "%LOG%" 2>&1
if errorlevel 1 echo   note: the journal needs an elevated prompt, run this window as administrator
powershell -NoProfile -Command "Select-String -LiteralPath '%LOG%' -Pattern 'AwgChain|repair|Repair|chain' -ErrorAction SilentlyContinue ^| ForEach-Object { $_.Line } ^| Set-Content -LiteralPath '%LOGS%\manager-chain-log.txt'"
echo.
echo  --- the last chain lines of the journal ---
powershell -NoProfile -Command "if (Test-Path -LiteralPath '%LOGS%\manager-chain-log.txt') { Get-Content -LiteralPath '%LOGS%\manager-chain-log.txt' -Tail 30 } else { 'nothing about the chain in the journal yet' }"
echo.
echo  The whole journal is at %LOG%, and both files go into awgchain-logs.zip.
goto end

rem ==========================================================================
rem  PATCH10 - the kill switch and the watchdog move into the manager
rem ==========================================================================
:cmd_patch10
set "LOG=%LOGS%\patch10-log.txt"
if not exist "%HERE%patch10.ps1" goto nopatch10ps
if not exist "%HERE%chainguard.go" goto nopatch10src
echo ==== %DATE% %TIME% patch10 %A2% ====> "%LOG%"
set "P10ARG="
if /i "%A2%"=="revert" set "P10ARG=-Revert"
if /i "%A2%"=="/revert" set "P10ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/3] patching the manager sources...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch10.ps1" -Client "%CLIENT%" -Here "%HERE0%" %P10ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch10fail
cd /d "%CLIENT%"
echo [2/3] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo [3/3] building awgchain-guard.exe...
if not exist "%CLIENT%\chainguard\main.go" goto p10_noguard
echo --- go build guard --->> "%LOG%"
go build -ldflags "-s -w" -trimpath -buildvcs=false -o amd64\awgchain-guard.exe .\chainguard >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
if not exist "%BIN%" mkdir "%BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%copy-guard.ps1" -Src "%CLIENT%\amd64\awgchain-guard.exe" -Dst "%GUARDEXE%" >> "%LOG%" 2>&1
for %%F in ("%GUARDEXE%") do echo guard size: %%~zF >> "%LOG%"
:p10_noguard
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 10 applied and everything rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui     then double-click %N2%
goto end

rem ==========================================================================
rem  AUTOGUARD - switch the automatic kill switch on or off
rem ==========================================================================
:cmd_autoguard
set "STATEDIR=%ProgramData%\AwgChain"
set "OFFFILE=%STATEDIR%\no-autoguard"
set "LOG=%LOGS%\autoguard-log.txt"
if not exist "%STATEDIR%" mkdir "%STATEDIR%"
echo ==== %DATE% %TIME% autoguard %A2% ====> "%LOG%"
if /i "%A2%"=="off" goto ag_off
if /i "%A2%"=="on" goto ag_on
goto ag_status

:ag_off
echo the chain must not arm the kill switch by itself> "%OFFFILE%"
echo AUTOGUARD=OFF>> "%LOG%"
echo  [OK] The chain will no longer arm the kill switch by itself.
echo       Use awgchain.bat kson if you want it armed.
goto ag_show

:ag_on
if exist "%OFFFILE%" del /f /q "%OFFFILE%"
echo AUTOGUARD=ON>> "%LOG%"
echo  [OK] The chain will arm the kill switch as soon as the top hop is up.
goto ag_show

:ag_status
if exist "%OFFFILE%" (echo AUTOGUARD=OFF>> "%LOG%") else (echo AUTOGUARD=ON>> "%LOG%")
if exist "%OFFFILE%" (echo  Automatic kill switch: OFF) else (echo  Automatic kill switch: ON)
goto ag_show

:ag_show
echo.
echo  --- guard process ---
tasklist /fi "imagename eq awgchain-guard.exe" 2>nul | findstr /i awgchain-guard >nul
if errorlevel 1 (echo  not running) else (echo  running)
tasklist /fi "imagename eq awgchain-guard.exe" >> "%LOG%" 2>&1
if exist "%STATEDIR%\guard-auto-log.txt" (
  echo.
  echo  --- last lines of the automatic guard log ---
  powershell -NoProfile -Command "Get-Content -LiteralPath '%STATEDIR%\guard-auto-log.txt' -Tail 12"
)
goto end

rem ==========================================================================
rem  PATCH9 - the pin route moves from the batch file into the tunnel service
rem ==========================================================================
:cmd_patch9
set "LOG=%LOGS%\patch9-log.txt"
if not exist "%HERE%patch9.ps1" goto nopatch9ps
if not exist "%HERE%pinroute.go" goto nopatch9src
echo ==== %DATE% %TIME% patch9 %A2% ====> "%LOG%"
set "P9ARG="
if /i "%A2%"=="revert" set "P9ARG=-Revert"
if /i "%A2%"=="/revert" set "P9ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/3] patching the tunnel sources...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch9.ps1" -Core "%CORE%" -Here "%HERE0%" %P9ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch9fail
cd /d "%CLIENT%"
echo [2/3] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo [3/3] building awgchain-guard.exe...
if not exist "%CLIENT%\chainguard\main.go" goto p9_noguard
echo --- go build guard --->> "%LOG%"
go build -ldflags "-s -w" -trimpath -buildvcs=false -o amd64\awgchain-guard.exe .\chainguard >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
if not exist "%BIN%" mkdir "%BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%copy-guard.ps1" -Src "%CLIENT%\amd64\awgchain-guard.exe" -Dst "%GUARDEXE%" >> "%LOG%" 2>&1
for %%F in ("%GUARDEXE%") do echo guard size: %%~zF >> "%LOG%"
:p9_noguard
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 9 applied and everything rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui     then double-click %N2%
goto end

rem ==========================================================================
rem  PATCH8 - chain ordering in the manager, so the interface can drive it
rem ==========================================================================
:cmd_patch8
set "LOG=%LOGS%\patch8-log.txt"
if not exist "%HERE%patch8.ps1" goto nopatch8ps
if not exist "%HERE%chainorder.go" goto nopatch8src
if not exist "%HERE%chainui.go" goto nopatch8src
echo ==== %DATE% %TIME% patch8 %A2% ====> "%LOG%"
set "P8ARG="
if /i "%A2%"=="revert" set "P8ARG=-Revert"
if /i "%A2%"=="/revert" set "P8ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/3] patching the manager sources...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch8.ps1" -Client "%CLIENT%" -Here "%HERE0%" %P8ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch8fail
cd /d "%CLIENT%"
echo [2/3] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo [3/3] building awgchain-guard.exe...
if not exist "%CLIENT%\chainguard\main.go" goto p8_noguard
echo --- go build guard --->> "%LOG%"
go build -ldflags "-s -w" -trimpath -buildvcs=false -o amd64\awgchain-guard.exe .\chainguard >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
if not exist "%BIN%" mkdir "%BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%copy-guard.ps1" -Src "%CLIENT%\amd64\awgchain-guard.exe" -Dst "%GUARDEXE%" >> "%LOG%" 2>&1
for %%F in ("%GUARDEXE%") do echo guard size: %%~zF >> "%LOG%"
:p8_noguard
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
echo.
echo  [OK] Patch 8 applied and everything rebuilt.
echo       Next:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat gui     then double-click %N2%
goto end

rem ==========================================================================
rem  DPAPI - delete the encrypted copies of the hop configs
rem ==========================================================================
:cmd_dpapi
set "LOG=%LOGS%\dpapi-log.txt"
echo ==== %DATE% %TIME% dpapi ====> "%LOG%"
echo --- configurations folder before --->> "%LOG%"
dir /b "%DATA%" >> "%LOG%" 2>&1
sc query AwgChainManager >nul 2>&1
if errorlevel 1 goto dpapi_nomgr
echo [1/3] stopping AwgChainManager so it cannot rewrite the folder...
echo --- stopping AwgChainManager --->> "%LOG%"
sc stop AwgChainManager >> "%LOG%" 2>&1
ping -n 3 127.0.0.1 >nul
:dpapi_nomgr
if not exist "%DATA%\*.conf.dpapi" goto dpapi_none
echo [2/3] taking ownership and deleting the encrypted copies...
echo --- takeown --->> "%LOG%"
takeown /f "%DATA%\*.conf.dpapi" /a >> "%LOG%" 2>&1
echo --- icacls --->> "%LOG%"
icacls "%DATA%\*.conf.dpapi" /grant *S-1-5-32-544:F >> "%LOG%" 2>&1
echo --- del --->> "%LOG%"
del /f /q "%DATA%\*.conf.dpapi" >> "%LOG%" 2>&1
goto dpapi_check
:dpapi_none
echo [2/3] there were no encrypted copies to delete.
echo none found>> "%LOG%"
:dpapi_check
echo [3/3] checking what is left...
echo --- configurations folder after --->> "%LOG%"
dir /b "%DATA%" >> "%LOG%" 2>&1
if exist "%DATA%\*.conf.dpapi" goto dpapifail
echo RESULT=OK>> "%LOG%"
type "%LOG%"
echo.
findstr /c:"fileIsChainHop" "%CORE%\conf\migration_windows.go" >nul 2>&1
if errorlevel 1 echo   warning: patch 7 is NOT in the sources. The manager will encrypt the
if errorlevel 1 echo            plain configs again and delete them on its next start.
if not exist "%C1%" echo   the plain hop 1 config is missing - run: awgchain.bat up
if not exist "%C2%" echo   the plain hop 2 config is missing - run: awgchain.bat up
echo [OK] No encrypted copies left in %DATA%
goto end

rem ==========================================================================
rem  GUI - open the graphical interface
rem ==========================================================================
:cmd_gui
set "LOG=%LOGS%\gui-log.txt"
echo ==== %DATE% %TIME% gui ====> "%LOG%"
if not exist "%EXE%" goto noguiexe
findstr /c:"chainHopByName" "%CLIENT%\manager\install.go" >nul 2>&1
if errorlevel 1 echo   warning: patch 6 is not in the sources, the interface may fight the chain
sc query AwgChainManager >nul 2>&1
if errorlevel 1 goto gui_nosvc
sc config AwgChainManager start= demand >> "%LOG%" 2>&1
:gui_nosvc
echo Opening the interface. It installs the manager service on first run.
echo If the chain is up you will be asked to confirm.
start "" "%EXE%"
echo STARTED=%EXE%>> "%LOG%"
goto end

rem ==========================================================================
rem  PATCH4 - UAPI pipe rename in amneziawg-go + UI guard, then rebuild
rem ==========================================================================
:cmd_patch4
set "LOG=%LOGS%\patch4-log.txt"
if not exist "%HERE%patch4.ps1" goto nopatch4ps
if not exist "%HERE%chainui.go" goto nopatch4src
echo ==== %DATE% %TIME% patch4 %A2% ====> "%LOG%"
set "P4ARG="
if /i "%A2%"=="revert" set "P4ARG=-Revert"
if /i "%A2%"=="/revert" set "P4ARG=-Revert"
call :goenv
if not exist "%GOROOT%\bin\go.exe" goto nogo
echo [1/3] patching the sources...
set "HERE0=%HERE:~0,-1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch4.ps1" -Client "%CLIENT%" -Here "%HERE0%" %P4ARG% >> "%LOG%" 2>&1
if errorlevel 1 goto patch4fail
cd /d "%CLIENT%"
echo [2/3] building the client...
echo --- go build client --->> "%LOG%"
go build -tags load_wgnt_from_rsrc -ldflags "-H windowsgui -s -w" -trimpath -buildvcs=false -o amd64\amneziawg.exe . >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
for %%F in ("%CLIENT%\amd64\amneziawg.exe") do echo client size: %%~zF >> "%LOG%"
echo [3/3] building awgchain-guard.exe...
if not exist "%CLIENT%\chainguard\main.go" goto p4_noguard
echo --- go build guard --->> "%LOG%"
go build -ldflags "-s -w" -trimpath -buildvcs=false -o amd64\awgchain-guard.exe .\chainguard >> "%LOG%" 2>&1
if errorlevel 1 goto buildfail
if not exist "%BIN%" mkdir "%BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%copy-guard.ps1" -Src "%CLIENT%\amd64\awgchain-guard.exe" -Dst "%GUARDEXE%" >> "%LOG%" 2>&1
for %%F in ("%GUARDEXE%") do echo guard size: %%~zF >> "%LOG%"
:p4_noguard
echo RESULT=OK>> "%LOG%"
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 30"
echo.
echo  [OK] Patch 4 applied and everything rebuilt.
echo       Next, to put the new binary in place:
echo         awgchain.bat down
echo         awgchain.bat install
echo         awgchain.bat up
goto end

rem ==========================================================================
rem  INSTALL - copy the built client into Program Files
rem ==========================================================================
:cmd_install
set "LOG=%LOGS%\install-bin-log.txt"
echo ==== %DATE% %TIME% install bin ====> "%LOG%"
if not exist "%CLIENT%\amd64\amneziawg.exe" goto noclientexe
echo === closing the interface and stopping every AwgChain service ===
call :freebin
if not exist "%BIN%" mkdir "%BIN%"
copy /y "%CLIENT%\amd64\amneziawg.exe" "%EXE%" >> "%LOG%" 2>&1
if errorlevel 1 goto copyfail
if exist "%BIN%\wintun.dll" goto haswintun
for /f "delims=" %%W in ('dir /s /b "%CLIENT%\.deps\wintun.dll" 2^>nul') do copy /y "%%W" "%BIN%\wintun.dll" >> "%LOG%" 2>&1
:haswintun
if exist "%CLIENT%\amd64\awgchain-guard.exe" copy /y "%CLIENT%\amd64\awgchain-guard.exe" "%GUARDEXE%" >> "%LOG%" 2>&1
for %%F in ("%EXE%") do echo awgchain.exe: %%~zF bytes>> "%LOG%"
if exist "%BIN%\wintun.dll" for %%F in ("%BIN%\wintun.dll") do echo wintun.dll: %%~zF bytes>> "%LOG%"
echo RESULT=OK>> "%LOG%"
type "%LOG%"
echo.
echo [OK] Installed. Raise the chain again: awgchain.bat up
goto end

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
rem ==========================================================================
rem  LOGS - zip everything for the chat
rem ==========================================================================
rem ========================= pack 38 commands =============================
:cmd_patch18
set "LOG=%LOGS%\patch18-log.txt"
if not exist "%HERE%patch18.ps1" goto nop38
echo ==== %DATE% %TIME% patch18 %A2% ====> "%LOG%"
set "P38ARG="
if /i "%A2%"=="revert" set "P38ARG=-Revert"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch18.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P38ARG% >> "%LOG%" 2>&1
type "%LOG%"
echo Log: %LOG%
goto end

:cmd_patch19
set "LOG=%LOGS%\patch19-log.txt"
if not exist "%HERE%patch19.ps1" goto nop38
echo ==== %DATE% %TIME% patch19 %A2% ====> "%LOG%"
set "P39ARG="
if /i "%A2%"=="revert" set "P39ARG=-Revert"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch19.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P39ARG% >> "%LOG%" 2>&1
type "%LOG%"
echo Log: %LOG%
goto end

:cmd_ipv6on
set "LOG=%LOGS%\ipv6-log.txt"
if not exist "%HERE%ipv6-lock.ps1" goto nop38
echo ==== %DATE% %TIME% ipv6 on ====> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%ipv6-lock.ps1" -On >> "%LOG%" 2>&1
type "%LOG%"
goto end

:cmd_ipv6off
set "LOG=%LOGS%\ipv6-log.txt"
if not exist "%HERE%ipv6-lock.ps1" goto nop38
echo ==== %DATE% %TIME% ipv6 off ====> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%ipv6-lock.ps1" -Off >> "%LOG%" 2>&1
type "%LOG%"
goto end

:cmd_ipv6chk
set "LOG=%LOGS%\ipv6-check-log.txt"
if not exist "%HERE%ipv6-check.ps1" goto nop38
echo ==== %DATE% %TIME% ipv6 check ====> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%ipv6-check.ps1" -Here "%HERE0%" >> "%LOG%" 2>&1
type "%LOG%"
echo Log: %LOG%
goto end

:cmd_stress
set "LOG=%LOGS%\stress-chain-log.txt"
if not exist "%HERE%stress-chain.ps1" goto nop38
set "CYC=%A2%"
if "%CYC%"=="" set "CYC=50"
set "SMODE=%A3%"
if "%SMODE%"=="" set "SMODE=ordered"
echo Running %CYC% cycles in mode %SMODE%, this takes a while.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%stress-chain.ps1" -Cycles %CYC% -Mode %SMODE% -Here "%HERE0%" -Logs "%LOGS%"
echo Report: %LOGS%\stress-chain.csv
goto end

:cmd_fixconfs
set "LOG=%LOGS%\fixconfs-log.txt"
if not exist "%HERE%fix-confs.ps1" goto nop38
set "FCARG="
if /i "%A2%"=="revert" set "FCARG=-Revert"
echo ==== %DATE% %TIME% fixconfs %A2% ====> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%fix-confs.ps1" -Folder "%HERE0%" %FCARG% >> "%LOG%" 2>&1
type "%LOG%"
goto end

:nop38
echo [FAIL] a pack 38 script is missing next to this file: %HERE%
echo Unpack the pack 38 zip into C:\vpn with replace and try again.
goto end

rem ==========================================================================
rem  APPLOG - the internal log of the client itself
rem ==========================================================================
:cmd_applog
set "OUT=%LOGS%\app-log.txt"
if not exist "%EXE%" goto applog_noexe
echo Dumping the client log, this takes a moment...
"%EXE%" /dumplog > "%OUT%" 2>&1
if not exist "%OUT%" goto applog_empty
for %%F in ("%OUT%") do echo %%~zF bytes: %OUT%
echo.
echo Now run: awgchain.bat logs
goto end

:applog_noexe
echo [FAIL] the client is not installed: %EXE%
goto end

:applog_empty
echo [FAIL] the log could not be written to %OUT%
goto end

rem ==========================================================================
rem  PATCH20 - repair counter and hop start retry
rem ==========================================================================
:cmd_patch20
set "LOG=%LOGS%\patch20-log.txt"
if not exist "%HERE%patch20.ps1" goto p20_missing
echo ==== %DATE% %TIME% patch20 %A2% ====> "%LOG%"
set "P20ARG="
if /i "%A2%"=="revert" set "P20ARG=-Revert"
if /i "%A2%"=="/revert" set "P20ARG=-Revert"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch20.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P20ARG%
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch20.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P20ARG% >> "%LOG%" 2>&1
echo.
echo Log: %LOG%
goto end

:p20_missing
echo [FAIL] patch20.ps1 is not next to awgchain.bat
goto end

rem ==========================================================================
rem  PATCH22 - the kill switch does not outlive the manager
rem ==========================================================================
:cmd_patch22
set "LOG=%LOGS%\patch22-log.txt"
if not exist "%HERE%patch22.ps1" goto p22_missing
echo ==== %DATE% %TIME% patch22 %A2% ====> "%LOG%"
set "P22ARG="
if /i "%A2%"=="revert" set "P22ARG=-Revert"
if /i "%A2%"=="/revert" set "P22ARG=-Revert"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch22.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P22ARG%
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch22.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P22ARG% >> "%LOG%" 2>&1
echo.
echo Log: %LOG%
goto end

:p22_missing
echo [FAIL] patch22.ps1 is not next to awgchain.bat
goto end

rem ==========================================================================
rem  KSSTOP - let go of the kill switch right now
rem ==========================================================================
:cmd_ksstop
if not exist "%GUARDEXE%" goto ksstop_nobin
echo Asking the kill switch to stand down...
"%GUARDEXE%" -stop
timeout /t 3 /nobreak >nul
tasklist /fi "imagename eq awgchain-guard.exe" | findstr /i awgchain-guard.exe >nul
if errorlevel 1 goto ksstop_done
echo It is still running, ending it the hard way.
taskkill /F /IM awgchain-guard.exe >nul 2>&1
:ksstop_done
echo [OK] the kill switch is gone, the internet is back
echo Note: the chain itself is untouched. Use awgchain.bat down to stop it.
goto end

:ksstop_nobin
echo [FAIL] the guard is not installed: %GUARDEXE%
goto end

rem ==========================================================================
rem  SRCDUMP - collect the repository sources for the chat
rem ==========================================================================
:cmd_srcdump
set "SRCZIP=%HERE%awgchain-src.zip"
set "SRCTMP=%TEMP%\awgchain-src"
if exist "%SRCZIP%" del /f /q "%SRCZIP%"
if exist "%SRCTMP%" rmdir /s /q "%SRCTMP%"
mkdir "%SRCTMP%\manager" 2>nul
mkdir "%SRCTMP%\chainguard" 2>nul
mkdir "%SRCTMP%\tunnel" 2>nul
mkdir "%SRCTMP%\conf" 2>nul
mkdir "%SRCTMP%\ui" 2>nul
copy /y "%CLIENT%\manager\*.go" "%SRCTMP%\manager\" >nul 2>&1
copy /y "%CLIENT%\chainguard\*.go" "%SRCTMP%\chainguard\" >nul 2>&1
copy /y "%CLIENT%\ui\*.go" "%SRCTMP%\ui\" >nul 2>&1
copy /y "%CORE%\tunnel\*.go" "%SRCTMP%\tunnel\" >nul 2>&1
copy /y "%CORE%\conf\*.go" "%SRCTMP%\conf\" >nul 2>&1
powershell -NoProfile -Command "Compress-Archive -Path '%SRCTMP%\*' -DestinationPath '%SRCZIP%' -Force"
rmdir /s /q "%SRCTMP%"
if not exist "%SRCZIP%" goto srcdump_fail
for %%F in ("%SRCZIP%") do echo %%~zF bytes: %SRCZIP%
echo.
echo Send awgchain-src.zip to the chat.
goto end

:srcdump_fail
echo [FAIL] the archive could not be written to %SRCZIP%
goto end

:cmd_logs
set "ZIP=%HERE%awgchain-logs.zip"
if exist "%ZIP%" del /f /q "%ZIP%"
powershell -NoProfile -Command "$files = Get-ChildItem -LiteralPath '%LOGS%' -Filter '*.txt' -ErrorAction SilentlyContinue; if ($files) { Compress-Archive -Path $files.FullName -DestinationPath '%ZIP%' -Force; 'files: ' + $files.Count } else { 'no logs found in %LOGS%' }"
if exist "%ZIP%" for %%F in ("%ZIP%") do echo %%~zF bytes: %ZIP%
echo.
echo Send awgchain-logs.zip to the chat.
goto end

rem ==========================================================================
rem  helpers
rem ==========================================================================
:setvar
set "K=%~1"
set "V=%~2"
if /I "%K%"=="HOP1" set "SRC1=%V%"
if /I "%K%"=="HOP2" set "SRC2=%V%"
if /I "%K%"=="DIAG" echo    %V%
exit /b 0

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
:goenv
set "GOROOT=%CLIENT%\.deps\go"
set "GOPATH=%CLIENT%\.deps\gopath"
set "PATH=%GOROOT%\bin;%PATH%"
set "GOOS=windows"
set "GOARCH=amd64"
set "CGO_ENABLED=0"
set "GOFLAGS="
exit /b 0

:drop
set "S=%~1"
sc query "%S%" >nul 2>&1
if errorlevel 1 goto dropdone
sc stop "%S%" >nul 2>&1
timeout /t 3 /nobreak >nul
sc delete "%S%" >nul 2>&1
timeout /t 2 /nobreak >nul
:dropdone
exit /b 0

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
set "PAIR=warpam"
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
:freebin
taskkill /f /im amneziawg.exe >> "%LOG%" 2>&1
taskkill /f /im awgchain.exe >> "%LOG%" 2>&1
taskkill /f /im awgchain-guard.exe >> "%LOG%" 2>&1
powershell -NoProfile -Command "Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'AwgChainTunnel*' } | ForEach-Object { sc.exe stop $_.Name | Out-Null; sc.exe delete $_.Name | Out-Null }" >> "%LOG%" 2>&1
sc stop AwgChainManager >> "%LOG%" 2>&1
sc delete AwgChainManager >> "%LOG%" 2>&1
timeout /t 4 /nobreak >nul
exit /b 0

:kill
set "S=%~1"
sc query "%S%" >nul 2>&1
if errorlevel 1 goto killdone
echo removing %S%
echo --- %S% --->> "%LOG%"
sc stop "%S%" >> "%LOG%" 2>&1
timeout /t 3 /nobreak >nul
sc delete "%S%" >> "%LOG%" 2>&1
:killdone
exit /b 0

:svcline
set "S=%~1"
set "TAG=%~2"
sc query "%S%" >nul 2>&1
if errorlevel 1 goto svcmissing
for /f "tokens=3" %%S in ('sc query "%S%" ^| findstr /i "STATE"') do echo   %TAG% : %%S
exit /b 0
:svcmissing
echo   %TAG% : not installed
exit /b 0

:snapshot
echo --- interfaces --->> "%LOG%"
powershell -NoProfile -Command "Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object ifIndex,InterfaceAlias,NlMtu,ConnectionState | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
echo --- ipv4 addresses --->> "%LOG%"
powershell -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object ifIndex,InterfaceAlias,IPAddress,PrefixLength | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
echo --- routes that matter --->> "%LOG%"
powershell -NoProfile -Command "Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0','0.0.0.0/1','128.0.0.0/1') -or $_.DestinationPrefix -like '*/32' } | Select-Object ifIndex,InterfaceAlias,DestinationPrefix,NextHop,RouteMetric | Sort-Object DestinationPrefix | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
echo --- dns servers --->> "%LOG%"
powershell -NoProfile -Command "Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object ifIndex,InterfaceAlias,ServerAddresses | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
echo --- mtu --->> "%LOG%"
netsh interface ipv4 show subinterfaces >> "%LOG%" 2>&1
exit /b 0

:counters
echo --- hop1 counters --->> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%uapi-stats.ps1" -Tunnel "%N1%" >> "%LOG%" 2>&1
echo --- hop2 counters --->> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%uapi-stats.ps1" -Tunnel "%N2%" >> "%LOG%" 2>&1
exit /b 0

:sample
echo   sample %~1
echo --- sample %~1 at %TIME% --->> "%LOG%"
call :counters
powershell -NoProfile -Command "Get-NetAdapterStatistics -Name '%N1%','%N2%' -ErrorAction SilentlyContinue | Select-Object Name,ReceivedBytes,SentBytes | Format-Table -AutoSize | Out-String -Width 200" >> "%LOG%" 2>&1
curl -s --max-time 15 -o NUL -w "reachability=%%{http_code} time=%%{time_total}\n" https://www.cloudflare.com/cdn-cgi/trace >> "%LOG%" 2>&1
exit /b 0

:probe
set "SZ=%~1"
echo ---- payload %SZ% bytes ---->> "%LOG%"
ping -n 2 -f -l %SZ% 1.1.1.1 >> "%LOG%" 2>&1
exit /b 0

:egress
set "OUT="
for /f "usebackq delims=" %%I in (`curl -s --max-time 15 https://api.ipify.org`) do set "OUT=%%I"
if not defined OUT echo   egress : no answer (network down?)
if defined OUT echo   egress : %OUT%
exit /b 0

rem ==========================================================================
rem  failures
rem ==========================================================================
:noconf
echo [FAIL] Could not find both .conf files in this folder.
echo        Put the WARP .conf and the Amnezia .conf next to awgchain.bat.
goto end

:nobin
echo [FAIL] %EXE% not found. Build and install it first:
echo        awgchain.bat build   then   awgchain.bat install
goto end

:noendpoint
echo [FAIL] No Endpoint found in the hop 2 config.
goto end

:hostname
echo [FAIL] hop 2 endpoint "%EP2%" is a hostname, not an IP address.
echo        Replace it with the server IP, otherwise the name lookup leaks
echo        and no host route can be pinned for it.
goto end

:conf1fail
echo [FAIL] Could not build the hop 1 config.
goto end

:conf2fail
echo [FAIL] Could not build the hop 2 config.
goto end

:screate1
echo [FAIL] sc create failed for hop 1. See %LOG%
goto end

:screate2
echo [FAIL] sc create failed for hop 2. See %LOG%
goto end

:nohop1
echo [FAIL] The %N1% adapter never appeared, hop 1 did not start.
sc query "%S1%" >> "%LOG%" 2>&1
"%EXE%" /dumplog >> "%LOG%" 2>&1
goto end

:nochain
echo [FAIL] %N2% is not up. Run: awgchain.bat up
goto end

:noguard
echo [FAIL] awgchain-guard.exe is missing. Build it: awgchain.bat build
goto end

:noguardps
echo [FAIL] guard-up.ps1 is missing next to awgchain.bat.
goto end

:noleakps
echo [FAIL] leak-test.ps1 is missing next to awgchain.bat.
goto end

:nodnsps
echo [FAIL] dns-lock.ps1 is missing next to awgchain.bat.
goto end

:nopatch3ps
echo [FAIL] apply-patch3.ps1 is missing next to awgchain.bat.
goto end

:nopatch6ps
echo patch6.ps1 was not found next to this script: %HERE%
goto end

:nopatch6src
echo chainmanager.go or chainui.go is missing next to this script: %HERE%
goto end

:patch6fail
echo.
echo  [FAIL] patch 6 did not apply cleanly. The log is here:
echo         %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch17ps
echo [FAIL] patch17.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 36 into the same folder.
goto end

:nopatch17src
echo [FAIL] chainbuild-ui.go is missing next to this script: %HERE%
echo        Unpack the whole pack 36 into the same folder.
goto end

:patch17fail
echo [FAIL] patch 17 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch16ps
echo [FAIL] patch16.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 35 into the same folder.
goto end

:nopatch16src
echo [FAIL] chainorder.go is missing next to this script: %HERE%
echo        Unpack the whole pack 35 into the same folder.
goto end

:patch16fail
echo [FAIL] patch 16 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch15ps
echo [FAIL] patch15.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 34 into the same folder.
goto end

:nopatch15src
echo [FAIL] chainbuild-ui.go is missing next to this script: %HERE%
echo        Unpack the whole pack 34 into the same folder.
goto end

:patch15fail
echo [FAIL] patch 15 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch14ps
echo [FAIL] patch14.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 33 into the same folder.
goto end

:nopatch14src
echo [FAIL] chainbuild-conf.go or chainbuild-ui.go is missing next to this script: %HERE%
echo        Unpack the whole pack 33 into the same folder.
goto end

:patch14fail
echo [FAIL] patch 14 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch13ps
echo [FAIL] patch13.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 32 into the same folder.
goto end

:nopatch13src
echo [FAIL] chainbuild-conf.go or chainbuild-ui.go is missing next to this script: %HERE%
echo        Unpack the whole pack 32 into the same folder.
goto end

:patch13fail
echo [FAIL] patch 13 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch12ps
echo [FAIL] patch12.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 31 into the same folder.
goto end

:nopatch12src
echo [FAIL] chainguard.go is missing next to this script: %HERE%
echo        Unpack the whole pack 31 into the same folder.
goto end

:patch12fail
echo [FAIL] patch 12 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch11ps
echo [FAIL] patch11.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 30 into the same folder.
goto end

:nopatch11src
echo [FAIL] guard-main.go or chainguard.go is missing next to this script: %HERE%
echo        Unpack the whole pack 30 into the same folder.
goto end

:patch11fail
echo [FAIL] patch 11 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch10ps
echo [FAIL] patch10.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 29 into the same folder.
goto end

:nopatch10src
echo [FAIL] chainguard.go is missing next to this script: %HERE%
echo        Unpack the whole pack 29 into the same folder.
goto end

:patch10fail
echo [FAIL] patch 10 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch9ps
echo [FAIL] patch9.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 28 into the same folder.
goto end

:nopatch9src
echo [FAIL] pinroute.go is missing next to this script: %HERE%
echo        Unpack the whole pack 28 into the same folder.
goto end

:patch9fail
echo [FAIL] patch 9 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch8ps
echo [FAIL] patch8.ps1 is missing next to this script: %HERE%
echo        Unpack the whole pack 27 into the same folder.
goto end

:nopatch8src
echo [FAIL] chainorder.go or chainui.go is missing next to this script: %HERE%
echo        Unpack the whole pack 27 into the same folder.
goto end

:patch8fail
echo [FAIL] patch 8 did not apply. The log is at %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:nopatch7ps
echo [FAIL] patch7.ps1 is missing next to this script: %HERE%
goto end

:nopatch7src
echo [FAIL] chainconf.go is missing next to this script: %HERE%
goto end

:patch7fail
echo.
echo  [FAIL] patch 7 did not apply cleanly. The log is here:
echo         %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:dpapifail
echo.
echo  [FAIL] Some .conf.dpapi files are still there. Most likely the manager
echo         service is holding them. Close the interface, then run again:
echo           awgchain.bat dpapi
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 30"
goto end

:noguiexe
echo The client is not installed yet: %EXE%
echo Run: awgchain.bat install
goto end

:nostatsps
echo [FAIL] uapi-stats.ps1 is missing next to this script.
goto end

:nopatch4ps
echo [FAIL] patch4.ps1 is missing next to this script.
goto end

:nopatch4src
echo [FAIL] chainui.go is missing next to this script.
goto end

:patch4fail
echo [FAIL] patch4.ps1 reported a problem. See %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 40"
goto end

:patch3fail
echo [FAIL] apply-patch3.ps1 failed. See %LOG%
goto end

:nocore
echo RESULT=FAIL reason=core-not-found>> "%LOG%"
echo [FAIL] The core repo was not found: %CORE%
goto end

:noclient
echo RESULT=FAIL reason=client-not-found>> "%LOG%"
echo [FAIL] The client repo was not found: %CLIENT%
goto end

:noclientexe
echo [FAIL] %CLIENT%\amd64\amneziawg.exe does not exist. Build it first.
goto end

:chainup
echo [FAIL] The chain is still installed. Run awgchain.bat down first,
echo        otherwise the running binary cannot be replaced.
goto end

:nosrc
echo RESULT=FAIL reason=source-missing>> "%LOG%"
echo [FAIL] chainfirewall.go or guard-main.go is missing next to this script.
goto end

:nogo
echo RESULT=FAIL reason=go-not-found>> "%LOG%"
echo [FAIL] Go was not found: %GOROOT%\bin\go.exe
goto end

:copyfail
echo RESULT=FAIL reason=copy>> "%LOG%"
echo [FAIL] A file could not be copied. See %LOG%
goto end

:buildfail
echo RESULT=FAIL reason=build>> "%LOG%"
echo [FAIL] The build failed. Send me %LOG%
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 30"
goto end

:end
echo.
if defined MENUMODE goto backtomenu
pause
goto quit

:backtomenu
pause
set "MENUMODE="
set "A2="
set "A3="
goto menu

:quit
endlocal
exit /b 0
