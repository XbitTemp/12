# AwgChain patch 4
#
# 1. Makes a local fork of amneziawg-go (copied out of the module cache),
#    renames the UAPI named pipe from ...\AmneziaWG\<tunnel> to
#    ...\AwgChain\<tunnel> so the manager and the tunnel finally agree.
# 2. Wires that fork into the client with a go.mod replace directive.
# 3. Drops chainui.go into the client and teaches main.go to refuse to open
#    the GUI while the chain is up (the UI would kill one of the hops).
#
# Every step prints [OK] or [FAIL] on its own line. Run again safely:
# all steps are idempotent. Undo with -Revert.

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Fork   = 'C:\dev\vpnchain\amneziawg-go',
  [string]$Here   = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

# A trailing backslash inside a quoted cmd argument escapes the closing quote,
# so "C:\vpn\" reaches this script as  C:\vpn"   . Clean the arguments first.
$Here = ('' + $Here).Trim().Trim('"').Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Client = ('' + $Client).Trim().Trim('"').Trim().TrimEnd('\')
$Fork = ('' + $Fork).Trim().Trim('"').Trim().TrimEnd('\')

$module  = 'github.com/amnezia-vpn/amneziawg-go/v3'
$oldPipe = 'Administrators\AmneziaWG\'
$newPipe = 'Administrators\AwgChain\'
$mainGo  = Join-Path $Client 'main.go'
$backup  = Join-Path $Client 'main.go.orig-p4'
$uiGo    = Join-Path $Client 'chainui.go'
$fails   = 0

function Say([string]$m)  { Write-Host $m }
function Ok([string]$m)   { Write-Host ('[OK] ' + $m) }
function Bad([string]$m)  { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Write-Text([string]$path, [string]$text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

Say '=================================================='
Say 'AwgChain patch 4 - UAPI pipe name and UI guard'
Say ('date   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('client : ' + $Client)
Say ('fork   : ' + $Fork)
Say '=================================================='

if (-not (Test-Path -LiteralPath (Join-Path $Client 'go.mod'))) {
  Bad ('the client repo was not found: ' + $Client)
  Say 'RESULT=FAIL'
  exit 1
}

Set-Location -LiteralPath $Client

# ---------------------------------------------------------------- revert ---
if ($Revert) {
  Say '--- revert ---'

  & go mod edit -dropreplace $module
  if ($LASTEXITCODE -eq 0) { Ok 'the replace directive was dropped from go.mod' }
  else { Bad 'go mod edit -dropreplace failed' }

  if (Test-Path -LiteralPath $backup) {
    Copy-Item -LiteralPath $backup -Destination $mainGo -Force
    Remove-Item -LiteralPath $backup -Force
    Ok 'main.go was restored from main.go.orig-p4'
  } else {
    Say '  no main.go backup, leaving main.go alone'
  }

  if (Test-Path -LiteralPath $uiGo) {
    Remove-Item -LiteralPath $uiGo -Force
    Ok 'chainui.go was removed'
  }

  Say ('  the fork folder is left in place: ' + $Fork)
  if ($fails -eq 0) { Say 'RESULT=REVERTED'; exit 0 }
  Say 'RESULT=FAIL'
  exit 1
}

# ------------------------------------------------------- 1. fork the module ---
Say '--- 1. local fork of amneziawg-go ---'

$haveFork = Test-Path -LiteralPath (Join-Path $Fork 'ipc\uapi_windows.go')
if ($haveFork) {
  Ok ('the fork already exists: ' + $Fork)
} else {
  & go mod download $module 2>&1 | ForEach-Object { Say ('  ' + $_) }

  $srcDir = ''
  $out = & go list -m -f '{{.Dir}}' $module 2>&1
  foreach ($line in @($out)) {
    $t = ('' + $line).Trim()
    if ($t -ne '' -and (Test-Path -LiteralPath $t)) { $srcDir = $t }
  }

  if ($srcDir -eq '') {
    Bad 'could not locate amneziawg-go in the module cache'
    Say ('  go list said: ' + ($out -join ' | '))
    Say 'RESULT=FAIL'
    exit 1
  }
  Say ('  module cache: ' + $srcDir)

  $null = New-Item -ItemType Directory -Path $Fork -Force
  $rc = Start-Process -FilePath 'robocopy.exe' -ArgumentList @(('"' + $srcDir + '"'), ('"' + $Fork + '"'), '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1') -Wait -PassThru -WindowStyle Hidden
  if ($rc.ExitCode -ge 8) {
    Bad ('robocopy failed with code ' + $rc.ExitCode)
    Say 'RESULT=FAIL'
    exit 1
  }

  # the module cache is read-only, the copy must not be
  & attrib -R ($Fork + '\*') /S /D

  if (Test-Path -LiteralPath (Join-Path $Fork 'ipc\uapi_windows.go')) {
    Ok ('the fork was created: ' + $Fork)
  } else {
    Bad 'the copy has no ipc\uapi_windows.go'
    Say 'RESULT=FAIL'
    exit 1
  }
}

# ------------------------------------------------------- 2. the pipe name ---
Say '--- 2. the UAPI pipe name ---'

$uapi = Join-Path $Fork 'ipc\uapi_windows.go'
$text = Get-Content -LiteralPath $uapi -Raw
if ($text.Contains($newPipe)) {
  Ok 'the pipe is already named AwgChain'
} elseif ($text.Contains($oldPipe)) {
  Write-Text $uapi ($text.Replace($oldPipe, $newPipe))
  Ok 'the pipe was renamed AmneziaWG -> AwgChain'
} else {
  Bad 'neither pipe name was found in ipc\uapi_windows.go'
}

foreach ($line in (Get-Content -LiteralPath $uapi)) {
  if ($line -match 'ProtectedPrefix') { Say ('  now: ' + $line.Trim()) }
}

# --------------------------------------------------- 3. wire it into go.mod ---
Say '--- 3. go.mod replace directive ---'

& go mod edit -replace ($module + '=' + $Fork)
if ($LASTEXITCODE -ne 0) { Bad 'go mod edit -replace failed' }

$resolved = ''
$out = & go list -m -f '{{.Dir}}' $module 2>&1
foreach ($line in @($out)) {
  $t = ('' + $line).Trim()
  if ($t -ne '' -and (Test-Path -LiteralPath $t)) { $resolved = $t }
}
if ($resolved -eq $Fork) { Ok ('the client now builds against ' + $resolved) }
else { Bad ('the module still resolves to ' + $resolved) }

# -------------------------------------------------------- 4. the UI guard ---
Say '--- 4. the UI guard ---'

$src = Join-Path $Here 'chainui.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('chainui.go was not found next to this script: ' + $src)
} else {
  Copy-Item -LiteralPath $src -Destination $uiGo -Force
  Ok 'chainui.go was copied into the client'
}

if (-not (Test-Path -LiteralPath $mainGo)) {
  Bad ('main.go was not found: ' + $mainGo)
} else {
  $mg = Get-Content -LiteralPath $mainGo -Raw
  if ($mg -match 'blockUIWhenChainIsUp') {
    Ok 'main.go already calls the guard'
  } else {
    if (-not (Test-Path -LiteralPath $backup)) {
      Copy-Item -LiteralPath $mainGo -Destination $backup -Force
      Say '  a copy of the original is kept as main.go.orig-p4'
    }

    $nl = "`n"
    if ($mg.Contains("`r`n")) { $nl = "`r`n" }

    # main.go uses CRLF, so \r has to be allowed before the end of the line
    $rx1 = New-Object System.Text.RegularExpressions.Regex('(?m)^([ \t]*)checkForAdminGroup\(\)[ \t]*\r?$')
    $before = $mg
    $mg = $rx1.Replace($mg, ('${1}blockUIWhenChainIsUp()' + $nl + '${1}checkForAdminGroup()'), 1)
    if ($mg -ne $before) { Ok 'main.go: the guard runs before the UI is raised' }
    else { Bad 'main.go: the checkForAdminGroup() call was not found' }

    $rx2 = New-Object System.Text.RegularExpressions.Regex('(?m)^([ \t]*)go ui\.WaitForRaiseUIThenQuit\(\)[ \t]*\r?$')
    $before = $mg
    $mg = $rx2.Replace($mg, ('${1}blockUIWhenChainIsUp()' + $nl + '${1}go ui.WaitForRaiseUIThenQuit()'), 1)
    if ($mg -ne $before) { Ok 'main.go: the guard runs before the manager service is installed' }
    else { Bad 'main.go: the WaitForRaiseUIThenQuit() call was not found' }

    Write-Text $mainGo $mg
  }
}

Say '=================================================='
if ($fails -eq 0) {
  Say 'RESULT=OK'
  exit 0
}
Say ('RESULT=FAIL failed steps: ' + $fails)
exit 1
