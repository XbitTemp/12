# AwgChain pack 42 - three new commands in awgchain.bat.
#
#   1. patch22    apply the patch that lets the kill switch go when the
#                 manager is gone
#   2. ksstop     ask a running awgchain-guard.exe to remove the kill switch
#                 and exit, with taskkill as the last resort
#   3. srcdump    zip the repository sources I still cannot see (manager,
#                 chainguard, tunnel, conf) into awgchain-src.zip so the next
#                 patch can be written against the real code
#
# Backup: awgchain.bat.orig-p42. Undo with -Revert. Re-running is safe.

param(
  [string]$Bat = 'C:\vpn\awgchain.bat',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$script:fails = 0

function Say([string]$m) { Write-Host $m }
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Skip([string]$m) { Write-Host ('[SKIP] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Crlf([string]$s) { return (($s -replace "`r`n", "`n") -replace "`n", "`r`n") }

function Write-Bat([string]$path, [string]$text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, (Crlf $text), $enc)
}

$backup = $Bat + '.orig-p42'

Say '=================================================='
Say 'AwgChain pack 42 - patch22, ksstop, srcdump'
Say ('date : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('bat  : ' + $Bat)
Say '=================================================='

if (-not (Test-Path -LiteralPath $Bat)) {
  Bad ('not found: ' + $Bat)
  Say 'RESULT=FAIL reason=missing'
  exit 1
}

if ($Revert) {
  if (Test-Path -LiteralPath $backup) {
    Copy-Item -LiteralPath $backup -Destination $Bat -Force
    Remove-Item -LiteralPath $backup -Force
    Ok 'awgchain.bat was restored from the backup'
  } else {
    Say '  no backup, leaving awgchain.bat alone'
  }
  Say 'RESULT=OK'
  exit 0
}

$text = [System.IO.File]::ReadAllText($Bat)

if (-not (Test-Path -LiteralPath $backup)) {
  Copy-Item -LiteralPath $Bat -Destination $backup -Force
  Say '  a copy of the original is kept as awgchain.bat.orig-p42'
}

# ------------------------------------------------ 1. the command list ---
if ($text -match ' patch22 ') {
  Skip 'the command list already knows patch22'
} else {
  $anchor = ' patch19 patch20 applog ipv6on '
  if ($text.IndexOf($anchor) -lt 0) {
    Bad 'could not find the command list of pack 41 in awgchain.bat'
  } else {
    $text = $text.Replace($anchor, ' patch19 patch20 patch22 applog srcdump ksstop ipv6on ')
    Ok 'patch22, srcdump and ksstop are accepted commands now'
  }
}

# ---------------------------------------------------- 2. the new blocks ---
if ($text -match ':cmd_patch22') {
  Skip 'the command blocks are already in place'
} else {
  $blockAnchor = "`r`n:cmd_logs`r`n"
  $plainAnchor = "`n:cmd_logs`n"
  $useAnchor = $blockAnchor
  if ($text.IndexOf($blockAnchor) -lt 0) { $useAnchor = $plainAnchor }
  if ($text.IndexOf($useAnchor) -lt 0) {
    Bad 'could not find the logs command in awgchain.bat'
  } else {
    $block = @'

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

'@
    $idx = $text.IndexOf($useAnchor)
    $text = $text.Substring(0, $idx) + (Crlf $block) + $text.Substring($idx)
    Ok 'the patch22, ksstop and srcdump blocks were added'
  }
}

if ($script:fails -gt 0) {
  Say ''
  Say 'RESULT=FAIL'
  exit 1
}

Write-Bat $Bat $text
Say ''
Say 'What to do next:'
Say '  awgchain.bat srcdump   send me awgchain-src.zip'
Say '  awgchain.bat patch22'
Say '  awgchain.bat build'
Say '  awgchain.bat install'
Say 'RESULT=OK'
exit 0
