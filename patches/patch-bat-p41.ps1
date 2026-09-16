# AwgChain pack 41 - three small changes in awgchain.bat.
#
#   1. new command: applog   dumps the internal log of the client into
#                            logs\app-log.txt with awgchain.exe /dumplog
#   2. build now stops awgchain-guard.exe first, so the copy step cannot fail
#      with "the process cannot access the file because it is being used by
#      another process" the way it did in pack 40
#   3. patch20 command, so the new patch is run the same way as the others
#
# Backup: awgchain.bat.orig-p41. Undo with -Revert. Re-running is safe.

param(
  [string]$Bat = 'C:\vpn\awgchain.bat',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

$fails = 0
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Skip([string]$m) { Write-Host ('[SKIP] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

$Bat = ('' + $Bat).Trim().Trim('"').Trim()
$backup = $Bat + '.orig-p41'

function Write-Bat([string]$path, [string]$text) {
  # a .bat file must stay CRLF and plain ASCII
  $text = $text -replace "`r`n", "`n"
  $text = $text -replace "`n", "`r`n"
  $enc = New-Object System.Text.ASCIIEncoding
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

if (-not (Test-Path -LiteralPath $Bat)) { Bad ('not found: ' + $Bat); Write-Host 'RESULT=FAIL'; exit 1 }

if ($Revert) {
  if (Test-Path -LiteralPath $backup) {
    Copy-Item -LiteralPath $backup -Destination $Bat -Force
    Remove-Item -LiteralPath $backup -Force
    Ok 'awgchain.bat restored from backup'
    Write-Host 'RESULT=OK'
    exit 0
  }
  Write-Host 'no backup found, leaving awgchain.bat alone'
  Write-Host 'RESULT=OK'
  exit 0
}

$text = [System.IO.File]::ReadAllText($Bat)
$changed = 0

if (-not (Test-Path -LiteralPath $backup)) {
  Copy-Item -LiteralPath $Bat -Destination $backup -Force
  Write-Host '  original kept as awgchain.bat.orig-p41'
}

# --- 1. the command list -----------------------------------------------------

if ($text -match 'VALID=[^\r\n]*\sapplog\s') {
  Skip 'applog is already in the command list'
} else {
  # the anchor has to be unique: bare ' patch19 ' also appears in the help
  # text and in one log line, and replacing those would break the file
  $a = ' patch19 ipv6on '
  if ($text.Contains($a)) {
    $text = $text.Replace($a, ' patch19 patch20 applog ipv6on ')
    $changed = $changed + 1
    Ok 'applog and patch20 added to the command list'
  } else {
    Bad 'anchor not found: the VALID command list'
  }
}

# --- 2. build stops the guard before it rebuilds it --------------------------

if ($text.Contains('taskkill /F /IM awgchain-guard.exe')) {
  Skip 'build already stops the guard first'
} else {
  $a = 'echo [4/4] building awgchain-guard.exe...'
  if ($text.Contains($a)) {
    $n = 'echo     stopping the running guard so its file can be replaced...' + "`r`n" +
         'taskkill /F /IM awgchain-guard.exe >nul 2>&1' + "`r`n" +
         'ping -n 3 127.0.0.1 >nul' + "`r`n" +
         $a
    $text = $text.Replace($a, $n)
    $changed = $changed + 1
    Ok 'build now stops awgchain-guard.exe before rebuilding it'
  } else {
    Bad 'anchor not found: the [4/4] line of cmd_build'
  }
}

# --- 3. the applog and patch20 blocks ----------------------------------------

if ($text.Contains(':cmd_applog')) {
  Skip 'the applog block is already there'
} else {
  $a = ':cmd_logs'
  if ($text.Contains($a)) {
    $block = 'rem ==========================================================================' + "`r`n" +
             'rem  APPLOG - the internal log of the client itself' + "`r`n" +
             'rem ==========================================================================' + "`r`n" +
             ':cmd_applog' + "`r`n" +
             'set "OUT=%LOGS%\app-log.txt"' + "`r`n" +
             'if not exist "%EXE%" goto applog_noexe' + "`r`n" +
             'echo Dumping the client log, this takes a moment...' + "`r`n" +
             '"%EXE%" /dumplog > "%OUT%" 2>&1' + "`r`n" +
             'if not exist "%OUT%" goto applog_empty' + "`r`n" +
             'for %%F in ("%OUT%") do echo %%~zF bytes: %OUT%' + "`r`n" +
             'echo.' + "`r`n" +
             'echo Now run: awgchain.bat logs' + "`r`n" +
             'goto end' + "`r`n" +
             '' + "`r`n" +
             ':applog_noexe' + "`r`n" +
             'echo [FAIL] the client is not installed: %EXE%' + "`r`n" +
             'goto end' + "`r`n" +
             '' + "`r`n" +
             ':applog_empty' + "`r`n" +
             'echo [FAIL] the log could not be written to %OUT%' + "`r`n" +
             'goto end' + "`r`n" +
             '' + "`r`n" +
             'rem ==========================================================================' + "`r`n" +
             'rem  PATCH20 - repair counter and hop start retry' + "`r`n" +
             'rem ==========================================================================' + "`r`n" +
             ':cmd_patch20' + "`r`n" +
             'set "LOG=%LOGS%\patch20-log.txt"' + "`r`n" +
             'if not exist "%HERE%patch20.ps1" goto p20_missing' + "`r`n" +
             'echo ==== %DATE% %TIME% patch20 %A2% ====> "%LOG%"' + "`r`n" +
             'set "P20ARG="' + "`r`n" +
             'if /i "%A2%"=="revert" set "P20ARG=-Revert"' + "`r`n" +
             'if /i "%A2%"=="/revert" set "P20ARG=-Revert"' + "`r`n" +
             'powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch20.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P20ARG%' + "`r`n" +
             'powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%patch20.ps1" -Client "%CLIENT%" -Core "%CORE%" -Here "%HERE0%" %P20ARG% >> "%LOG%" 2>&1' + "`r`n" +
             'echo.' + "`r`n" +
             'echo Log: %LOG%' + "`r`n" +
             'goto end' + "`r`n" +
             '' + "`r`n" +
             ':p20_missing' + "`r`n" +
             'echo [FAIL] patch20.ps1 is not next to awgchain.bat' + "`r`n" +
             'goto end' + "`r`n" +
             '' + "`r`n" +
             $a
    $text = $text.Replace($a, $block)
    $changed = $changed + 1
    Ok 'the applog and patch20 blocks were added'
  } else {
    Bad 'anchor not found: the cmd_logs label'
  }
}

if ($changed -gt 0) { Write-Bat $Bat $text }

if ($fails -gt 0) {
  Write-Host ''
  Write-Host 'RESULT=FAIL'
  exit 1
}

Write-Host ''
Write-Host 'RESULT=OK'
Write-Host 'Check it with:  awgchain.bat help'
exit 0
