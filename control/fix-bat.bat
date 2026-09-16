@echo off
setlocal
rem ==========================================================================
rem  AwgChain pack 37 - one click fix for the control panel
rem   * rewrites the broken pair detection (that is why verify printed
rem     "[FAIL]   is not up" with an empty tunnel name)
rem   * adds the new command:  awgchain.bat vars
rem   * removes the old hardcoded tunnel names from the hints
rem
rem  Usage:  fix-bat.bat            apply
rem          fix-bat.bat revert     go back to the previous control panel
rem ==========================================================================

set "HERE=%~dp0"
set "BAT=%HERE%awgchain.bat"
set "LOGS=%HERE%logs"
if not exist "%LOGS%" mkdir "%LOGS%"
set "LOG=%LOGS%\patch-bat-log.txt"

net session >nul 2>&1
if errorlevel 1 goto elevate
goto run

:elevate
echo Requesting administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
exit /b 0

:run
if not exist "%BAT%" goto nobat
if not exist "%HERE%patch-bat.ps1" goto nops

set "ARG="
if /i "%~1"=="revert" set "ARG=-Revert"

echo ==== %DATE% %TIME% patch-bat %ARG% ====> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch-bat.ps1" -Bat "%BAT%" %ARG% >> "%LOG%" 2>&1
type "%LOG%"
echo.
findstr /c:"RESULT=OK" "%LOG%" >nul
if errorlevel 1 goto maybe
echo [OK] The control panel is patched. Now run:  awgchain.bat vars
goto done

:maybe
findstr /c:"RESULT=REVERTED" "%LOG%" >nul
if errorlevel 1 goto failed
echo [OK] The control panel was rolled back.
goto done

:failed
echo [FAIL] Something did not apply. Send me %LOG%
goto done

:nobat
echo [FAIL] awgchain.bat is not in this folder: %HERE%
echo        Unzip the whole pack into C:\vpn next to awgchain.bat.
goto done

:nops
echo [FAIL] patch-bat.ps1 is missing next to this file.
goto done

:done
echo.
pause
endlocal
exit /b 0
