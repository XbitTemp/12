@echo off
setlocal EnableDelayedExpansion

rem ==========================================================
rem  AwgChain watchdog
rem    awgchain-watch.bat start [interval]   watch + persistent lock
rem    awgchain-watch.bat nolock [interval]  watch only, no lock
rem    awgchain-watch.bat once               one health check, then exit
rem    awgchain-watch.bat stop               ask the watchdog to exit
rem    awgchain-watch.bat status             show the current state
rem ==========================================================

set "HERE=%~dp0"
set "LOGS=%HERE%logs"
set "CMD=%~1"
set "ARG=%~2"
if "%CMD%"=="" set "CMD=start"

if /i "%CMD%"=="stop" goto do_stop
if /i "%CMD%"=="status" goto do_status
if /i "%CMD%"=="start" goto need_admin
if /i "%CMD%"=="nolock" goto need_admin
if /i "%CMD%"=="once" goto need_admin
if /i "%CMD%"=="help" goto usage
if /i "%CMD%"=="-h" goto usage
if /i "%CMD%"=="/?" goto usage
goto usage

:usage
echo.
echo AwgChain watchdog
echo.
echo   awgchain-watch.bat start [interval]   watch the chain, keep the kill switch armed
echo   awgchain-watch.bat nolock [interval]  watch the chain, do not touch the kill switch
echo   awgchain-watch.bat once               run a single health check and exit
echo   awgchain-watch.bat stop               ask a running watchdog to exit
echo   awgchain-watch.bat status             print the last known state
echo.
echo   interval defaults to 10 seconds
echo.
goto end

:need_admin
net session >nul 2>&1
if errorlevel 1 goto elevate
goto do_start

:elevate
echo Asking for administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%CMD%','%ARG%' -Verb RunAs"
goto quit

:do_start
if not exist "%LOGS%" mkdir "%LOGS%"
if not exist "%HERE%watchdog.ps1" goto nows
if not exist "%HERE%guard-up.ps1" goto nogu

set "INT=%ARG%"
if "%INT%"=="" set "INT=10"

set "LOCK=-WithLock"
if /i "%CMD%"=="nolock" set "LOCK=-NoLock"

set "ONCE="
if /i "%CMD%"=="once" set "ONCE=-Once"
if /i "%CMD%"=="once" set "LOCK=-NoLock"

echo ==================================================
echo AwgChain watchdog
echo command : %CMD%
echo interval: %INT% seconds
echo logs    : %LOGS%
echo ==================================================
echo Leave this window open. Stop it with Ctrl+C or:  awgchain-watch.bat stop
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%watchdog.ps1" -Interval %INT% %LOCK% %ONCE% -LogDir "%LOGS%"
goto end

:do_stop
if not exist "%LOGS%" mkdir "%LOGS%"
echo stop> "%LOGS%\watchdog.stop"
echo Stop requested. The watchdog exits within one interval.
echo The kill switch is NOT released by this. Use:  awgchain.bat ks off
goto end

:do_status
echo ==================================================
echo AwgChain watchdog status
echo ==================================================
if not exist "%LOGS%\watchdog-state.txt" goto nostate
type "%LOGS%\watchdog-state.txt"
goto tail

:nostate
echo No state file yet - the watchdog has not run from this folder.

:tail
echo.
echo --- guard process ---
tasklist /fi "imagename eq awgchain-guard.exe" 2>nul | findstr /i awgchain-guard
if errorlevel 1 echo the guard is not running, the kill switch is off
echo.
echo --- last 20 log lines ---
if not exist "%LOGS%\watchdog-log.txt" goto end
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOGS%\watchdog-log.txt' -Tail 20"
goto end

:nows
echo [FAIL] watchdog.ps1 was not found next to this file
goto end

:nogu
echo [FAIL] guard-up.ps1 was not found next to this file
goto end

:end
echo.
pause

:quit
endlocal
