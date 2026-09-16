@echo off
setlocal EnableDelayedExpansion
title AwgChain - guided test run (pack 23)

rem ==========================================================
rem  Run this file. Press a key at each step. Send me the zip.
rem ==========================================================

set "HERE=%~dp0"
set "LOGS=%HERE%logs"
set "BIN=C:\Program Files\AwgChain\bin"
set "GUARD=%BIN%\awgchain-guard.exe"
set "SVC1=AwgChainTunnel$hop1-warp"
set "ZIP=%HERE%awgchain-test-logs.zip"
set "STEP=0"

net session >nul 2>&1
if errorlevel 1 goto elevate
goto checks

:elevate
echo Asking for administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
goto quit

:checks
if not exist "%HERE%guard-up.ps1" goto missing_gu
if not exist "%HERE%watchdog.ps1" goto missing_wd
if not exist "%HERE%leak-test.ps1" goto missing_lt
if not exist "%GUARD%" goto missing_bin
if not exist "%LOGS%" mkdir "%LOGS%"
del /q "%LOGS%\step*.txt" >nul 2>&1

cls
echo ==========================================================
echo   AwgChain - guided test run
echo ==========================================================
echo.
echo   There are 6 steps. I will tell you what each one does
echo   before it runs. Press a key to go on, close the window
echo   to stop.
echo.
echo   1  health check         nothing is changed
echo   2  arm the kill switch  persistent lock on
echo   3  leak test            all six must pass
echo   4  break hop 1 on purpose and watch the repair
echo   5  leak test again      all six must pass again
echo   6  release everything and pack the logs
echo.
echo   If anything goes wrong and you lose the network:
echo     close this window, then run
 echo     "%GUARD%" -stop
echo   or just reboot. Nothing survives a restart.
echo.
echo   Your local network stays allowed the whole time,
echo   so RDP to this machine keeps working.
echo.
pause

:step1
set "STEP=1"
cls
echo ==========================================================
echo  STEP 1 of 6 - health check
echo ==========================================================
echo.
echo  Reads the state of both tunnels and tries one connection
echo  through the chain. Changes nothing at all.
echo.
pause
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%watchdog.ps1" -Once -NoLock -LogDir "%LOGS%" > "%LOGS%\step1-precheck.txt" 2>&1
type "%LOGS%\step1-precheck.txt"
echo.
findstr /c:"HEALTH=OK" "%LOGS%\step1-precheck.txt" >nul
if errorlevel 1 goto step1_bad
echo  [OK] the chain is healthy
echo.
pause
goto step2

:step1_bad
echo  [WARN] the chain is not healthy yet.
echo  The watchdog tried to bring it up. Look at the lines above.
echo  If it says RECOVERY=OK or the tunnels are now up, carry on.
echo  If not, stop here and send me the logs from step 6.
echo.
pause
goto step2

:step2
set "STEP=2"
cls
echo ==========================================================
echo  STEP 2 of 6 - arm the kill switch
echo ==========================================================
echo.
echo  Installs the firewall rules. From this moment nothing
echo  leaves this machine except through the chain.
echo.
echo  This is the persistent mode - it will NOT expire on its
echo  own during the test. Step 6 releases it.
echo.
pause
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%guard-up.ps1" -Persist -LogDir "%LOGS%" > "%LOGS%\step2-lock.txt" 2>&1
type "%LOGS%\step2-lock.txt"
echo.
findstr /c:"GUARD=UP" "%LOGS%\step2-lock.txt" >nul
if errorlevel 1 goto step2_bad
echo  [OK] the kill switch is armed
echo.
pause
goto step3

:step2_bad
echo  [FAIL] the lock did not arm. Nothing was installed.
echo  Skipping to step 6 to collect the logs.
echo.
pause
goto step6

:step3
set "STEP=3"
cls
echo ==========================================================
echo  STEP 3 of 6 - leak test with the lock on
echo ==========================================================
echo.
echo  Six checks. Tests 2 and 4 are the ones that used to fail
echo  before the kill switch existed.
echo.
pause
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%leak-test.ps1" > "%LOGS%\step3-leak-locked.txt" 2>&1
type "%LOGS%\step3-leak-locked.txt" | findstr /i "TEST egress guard"
echo.
findstr /c:"=FAIL" "%LOGS%\step3-leak-locked.txt" >nul
if errorlevel 1 goto step3_ok
echo  [WARN] at least one test failed - the full output is in the log
echo.
pause
goto step4

:step3_ok
echo  [OK] six out of six
echo.
pause
goto step4

:step4
set "STEP=4"
cls
echo ==========================================================
echo  STEP 4 of 6 - break hop 1 on purpose
echo ==========================================================
echo.
echo  This stops the WARP tunnel under the chain. Your internet
echo  will go dead for about half a minute. That is the point.
echo.
echo  The watchdog then puts everything back in the right order:
echo    hop 2 down, hop 1 down, hop 1 up, pin route, hop 2 up.
echo  The kill switch stays armed the whole time, so nothing
echo  escapes while the chain is broken.
echo.
echo  Do not touch anything. It can take up to 2 minutes.
echo.
pause
echo.
echo  stopping %SVC1% ...
sc stop "%SVC1%" > "%LOGS%\step4-recovery.txt" 2>&1
timeout /t 8 /nobreak >nul
sc query "%SVC1%" >> "%LOGS%\step4-recovery.txt" 2>&1
echo  watching...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%watchdog.ps1" -Interval 5 -FailsBeforeRecovery 1 -StopAfterRecovery -NoColdStart -Duration 240 -NoLock -LogDir "%LOGS%" >> "%LOGS%\step4-recovery.txt" 2>&1
type "%LOGS%\step4-recovery.txt"
echo.
findstr /c:"RECOVERY=OK" "%LOGS%\step4-recovery.txt" >nul
if not errorlevel 1 goto step4_ok
findstr /c:"reason=recovered" "%LOGS%\step4-recovery.txt" >nul
if not errorlevel 1 goto step4_ok
findstr /c:"RECOVERY=OK" "%LOGS%\watchdog-log.txt" >nul
if not errorlevel 1 goto step4_ok
findstr /c:"reason=recovered" "%LOGS%\watchdog-log.txt" >nul
if errorlevel 1 goto step4_bad

:step4_ok
echo  [OK] the chain repaired itself
echo.
pause
goto step5

:step4_bad
echo  [FAIL] the repair did not finish. Carry on anyway -
echo  step 6 collects the logs and I will read them.
echo.
pause
goto step5

:step5
set "STEP=5"
cls
echo ==========================================================
echo  STEP 5 of 6 - leak test after the repair
echo ==========================================================
echo.
echo  Same six checks. If they still pass, the chain came back
echo  correctly and hop 2 did not slip out to the open internet
echo  while hop 1 was down.
echo.
pause
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%leak-test.ps1" > "%LOGS%\step5-leak-after.txt" 2>&1
type "%LOGS%\step5-leak-after.txt" | findstr /i "TEST egress guard"
echo.
findstr /c:"=FAIL" "%LOGS%\step5-leak-after.txt" >nul
if errorlevel 1 goto step5_ok
echo  [WARN] at least one test failed - the log has the details
echo.
pause
goto step6

:step5_ok
echo  [OK] six out of six after the repair
echo.
pause
goto step6

:step6
set "STEP=6"
cls
echo ==========================================================
echo  STEP 6 of 6 - release and collect
echo ==========================================================
echo.
echo  Removes the firewall rules and packs every log into one
echo  zip file for you to send me.
echo.
pause
echo.
"%GUARD%" -stop > "%LOGS%\step6-unlock.txt" 2>&1
type "%LOGS%\step6-unlock.txt"
timeout /t 3 /nobreak >nul

echo.
echo  --- checking that the lock is really gone ---
tasklist /fi "imagename eq awgchain-guard.exe" 2>nul | findstr /i awgchain-guard
if errorlevel 1 goto released
echo  the graceful stop did not take, closing the guard directly
taskkill /f /im awgchain-guard.exe >> "%LOGS%\step6-unlock.txt" 2>&1
timeout /t 3 /nobreak >nul
tasklist /fi "imagename eq awgchain-guard.exe" 2>nul | findstr /i awgchain-guard >nul
if errorlevel 1 goto released
echo  [FAIL] the guard is still alive. Reboot to clear the rules.
goto packing

:released
echo  [OK] the guard is gone, the firewall rules went with it
ping -n 3 1.1.1.1 >> "%LOGS%\step6-unlock.txt" 2>&1

:packing
echo.
echo  --- packing the logs ---
if exist "%ZIP%" del /q "%ZIP%"
powershell -NoProfile -Command "Compress-Archive -Path '%LOGS%\*.txt' -DestinationPath '%ZIP%' -Force"
if not exist "%ZIP%" goto nozip
echo.
echo ==========================================================
echo   DONE
echo ==========================================================
echo.
echo   Send me this file:
echo   %ZIP%
echo.
explorer /select,"%ZIP%"
goto end

:nozip
echo  [FAIL] could not build the zip. Send me the whole folder:
echo  %LOGS%
goto end

:missing_gu
echo [FAIL] guard-up.ps1 is not next to this file
goto end

:missing_wd
echo [FAIL] watchdog.ps1 is not next to this file
goto end

:missing_lt
echo [FAIL] leak-test.ps1 is not next to this file
echo        it came in pack 16, copy it into this folder
goto end

:missing_bin
echo [FAIL] the guard binary is missing:
echo        %GUARD%
echo        run  awgchain.bat build  first
goto end

:end
echo.
pause

:quit
endlocal
