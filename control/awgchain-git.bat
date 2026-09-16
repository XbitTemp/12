@echo off
setlocal enableextensions
rem ==========================================================================
rem  awgchain-git.bat - publish the AwgChain sources on GitHub
rem
rem  The private material NEVER leaves the machine: .conf files, .dpapi
rem  copies, logs, .exe files and the .orig-* backups are all left out, and a
rem  .gitignore repeats that rule inside the repository.
rem
rem  Commands
rem    awgchain-git.bat init https://github.com/user/awgchain.git
rem    awgchain-git.bat push "a short message"
rem    awgchain-git.bat status
rem    awgchain-git.bat list
rem    awgchain-git.bat help
rem ==========================================================================

set "HERE0=%~dp0"
set "HERE=%HERE0%"
set "WORK=%HERE%repo"
set "CLIENT=C:\dev\vpnchain\amneziawg-windows-client"
set "CORE=C:\dev\vpnchain\amneziawg-windows"
set "REMOTEFILE=%HERE%.git-remote.txt"

set "CMD=%~1"
set "ARG=%~2"
if "%CMD%"=="" set "CMD=help"

where git >nul 2>&1
if errorlevel 1 goto nogit

if /i "%CMD%"=="help" goto cmd_help
if /i "%CMD%"=="init" goto cmd_init
if /i "%CMD%"=="push" goto cmd_push
if /i "%CMD%"=="status" goto cmd_status
if /i "%CMD%"=="list" goto cmd_list
echo Unknown command "%CMD%".
goto cmd_help

:cmd_help
echo.
echo awgchain-git.bat - publish the sources on GitHub
echo.
echo   awgchain-git.bat init ^<url^>     create the local repository and remember the remote
echo   awgchain-git.bat push "message"  collect the files, commit and push
echo   awgchain-git.bat status          git status of the publication repository
echo   awgchain-git.bat list            show what WOULD be published, publish nothing
echo.
echo Never published: *.conf, *.dpapi, logs, *.exe, *.zip, *.orig-*
echo Repository folder: %WORK%
goto end

rem ==========================================================================
rem  collect - build the publication tree out of C:\vpn and the two repos
rem ==========================================================================
:collect
if not exist "%WORK%" mkdir "%WORK%"
for %%D in (control patches scripts fork-sources templates docs upstream-manager upstream-tunnel upstream-conf) do if not exist "%WORK%\%%D" mkdir "%WORK%\%%D"

copy /y "%HERE%awgchain.bat" "%WORK%\control\" >nul 2>&1
copy /y "%HERE%awgchain-watch.bat" "%WORK%\control\" >nul 2>&1
copy /y "%HERE%awgchain-git.bat" "%WORK%\control\" >nul 2>&1
copy /y "%HERE%awgtest.bat" "%WORK%\control\" >nul 2>&1
copy /y "%HERE%fix-bat.bat" "%WORK%\control\" >nul 2>&1

copy /y "%HERE%patch*.ps1" "%WORK%\patches\" >nul 2>&1
copy /y "%HERE%apply-patch*.ps1" "%WORK%\patches\" >nul 2>&1

for %%F in ("%HERE%*.ps1") do call :onescript "%%~F"

copy /y "%HERE%*.go" "%WORK%\fork-sources\" >nul 2>&1
copy /y "%HERE%*.go.txt" "%WORK%\templates\" >nul 2>&1
copy /y "%HERE%README*.txt" "%WORK%\docs\" >nul 2>&1

rem the current state of the two repositories, source only
copy /y "%CLIENT%\manager\*.go" "%WORK%\upstream-manager\" >nul 2>&1
copy /y "%CLIENT%\chainguard\*.go" "%WORK%\upstream-manager\" >nul 2>&1
copy /y "%CORE%\tunnel\*.go" "%WORK%\upstream-tunnel\" >nul 2>&1
copy /y "%CORE%\conf\*.go" "%WORK%\upstream-conf\" >nul 2>&1

rem anything that must never be published, in case a copy above caught it
del /f /q "%WORK%\*.conf" >nul 2>&1
del /f /q "%WORK%\*\*.conf" >nul 2>&1
del /f /q "%WORK%\*\*.dpapi" >nul 2>&1
del /f /q "%WORK%\*\*.exe" >nul 2>&1
del /f /q "%WORK%\*\*.zip" >nul 2>&1
for /r "%WORK%" %%F in (*.orig-*) do del /f /q "%%~F" >nul 2>&1
exit /b 0

:onescript
set "SP=%~1"
set "SN=%~nx1"
echo %SN%| findstr /i /b "patch" >nul
if not errorlevel 1 exit /b 0
echo %SN%| findstr /i /b "apply-patch" >nul
if not errorlevel 1 exit /b 0
copy /y "%SP%" "%WORK%\scripts\" >nul 2>&1
exit /b 0

rem ==========================================================================
rem  write the .gitignore and a short README.md
rem ==========================================================================
:writemeta
> "%WORK%\.gitignore" echo # never publish keys, live configs or local rubbish
>> "%WORK%\.gitignore" echo *.conf
>> "%WORK%\.gitignore" echo *.dpapi
>> "%WORK%\.gitignore" echo *.exe
>> "%WORK%\.gitignore" echo *.dll
>> "%WORK%\.gitignore" echo *.zip
>> "%WORK%\.gitignore" echo *.orig-*
>> "%WORK%\.gitignore" echo logs/
>> "%WORK%\.gitignore" echo *.log
>> "%WORK%\.gitignore" echo .git-remote.txt

if exist "%WORK%\README.md" exit /b 0
> "%WORK%\README.md" echo # AwgChain
>> "%WORK%\README.md" echo.
>> "%WORK%\README.md" echo A two hop chain for the AmneziaWG Windows client: apps -^> hop 2 -^> hop 1 -^> ISP.
>> "%WORK%\README.md" echo.
>> "%WORK%\README.md" echo * `control/`  the awgchain.bat control panel
>> "%WORK%\README.md" echo * `patches/`  the patch scripts applied to the upstream client
>> "%WORK%\README.md" echo * `scripts/`  helper scripts: stress test, MTU probe, leak test, locks
>> "%WORK%\README.md" echo * `fork-sources/`  the Go files of the fork
>> "%WORK%\README.md" echo * `upstream-*/`  the current state of the patched repositories
>> "%WORK%\README.md" echo.
>> "%WORK%\README.md" echo Upstream: https://github.com/amnezia-vpn/amneziawg-windows-client
>> "%WORK%\README.md" echo.
>> "%WORK%\README.md" echo No keys and no working configuration files are published here.
exit /b 0

rem ==========================================================================
rem  LIST - show what would be published
rem ==========================================================================
:cmd_list
call :collect
call :writemeta
echo Publication tree: %WORK%
echo.
for /r "%WORK%" %%F in (*) do echo %%~F| findstr /v /i "\\.git\\" 
echo.
echo Nothing was sent anywhere.
goto end

rem ==========================================================================
rem  INIT - create the repository and remember the remote
rem ==========================================================================
:cmd_init
if "%ARG%"=="" goto init_nourl
call :collect
call :writemeta
pushd "%WORK%"
if not exist ".git" git init -b main
git remote remove origin >nul 2>&1
git remote add origin "%ARG%"
git add -A
git -c user.useConfigOnly=false commit -m "AwgChain: first publication" 2>nul
if errorlevel 1 echo   nothing to commit, or git needs user.name and user.email first
popd
> "%REMOTEFILE%" echo %ARG%
echo.
echo [OK] the repository is ready: %WORK%
echo Remote: %ARG%
echo.
echo If git asked for an identity, run once:
echo   git config --global user.name "Xbit"
echo   git config --global user.email "tempxbit@proton.me"
echo.
echo Then publish with:
echo   awgchain-git.bat push "first publication"
goto end

:init_nourl
echo [FAIL] give the address of the empty GitHub repository, for example:
echo   awgchain-git.bat init https://github.com/Xbit/awgchain.git
goto end

rem ==========================================================================
rem  PUSH - collect, commit, push
rem ==========================================================================
:cmd_push
if not exist "%WORK%\.git" goto push_noinit
set "MSG=%ARG%"
if "%MSG%"=="" set "MSG=AwgChain: update"
call :collect
call :writemeta
pushd "%WORK%"
git add -A
git status --short
git commit -m "%MSG%"
if errorlevel 1 echo   nothing new to commit, pushing what is there anyway
git push -u origin HEAD
if errorlevel 1 goto push_failed
popd
echo.
echo [OK] the sources are on GitHub
goto end

:push_failed
popd
echo.
echo [FAIL] the push did not go through. The usual reasons:
echo   - GitHub asks for a login: use a personal access token as the password
echo   - the repository is not empty: run   git pull --rebase origin main   in %WORK%
goto end

:push_noinit
echo [FAIL] there is no repository yet. Run first:
echo   awgchain-git.bat init https://github.com/user/awgchain.git
goto end

rem ==========================================================================
rem  STATUS
rem ==========================================================================
:cmd_status
if not exist "%WORK%\.git" goto push_noinit
pushd "%WORK%"
git status
git log --oneline -5
popd
goto end

:nogit
echo [FAIL] git is not installed or not in PATH.
echo Install it once with:
echo   winget install --id Git.Git -e
echo Then open a new command window and try again.
goto end

:end
endlocal
exit /b 0
