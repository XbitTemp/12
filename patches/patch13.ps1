# AwgChain patch 13 - build the chain from the graphical interface
#
#   1. conf\writer.go      save PinEndpointVia when a config is written
#   2. conf\chainbuild.go   new file: turn two plain configs into two hops
#   3. ui\chainbuild.go     new file: the dialog and the wiring
#   4. ui\tunnelspage.go    new menu entry: Build a chain from two configs...
#
# Files are backed up once as <name>.orig-p13. Undo with -Revert. Re-running
# is safe.

param(
  [string]$Client = 'C:\dev\vpnchain\amneziawg-windows-client',
  [string]$Core = 'C:\dev\vpnchain\amneziawg-windows',
  [string]$Here = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

$Here = ('' + $Here).Trim().Trim('"').Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Client = ('' + $Client).Trim().Trim('"').Trim().TrimEnd('\')
$Core = ('' + $Core).Trim().Trim('"').Trim().TrimEnd('\')

$fails = 0

function Say([string]$m) { Write-Host $m }
function Ok([string]$m)  { Write-Host ('[OK] ' + $m) }
function Bad([string]$m) { Write-Host ('[FAIL] ' + $m); $script:fails = $script:fails + 1 }

function Write-Text([string]$path, [string]$text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Backup-Once([string]$path) {
  $b = $path + '.orig-p13'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p13'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Write-Host ('[OK] ' + $label + ' was restored from the backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

function Insert-Before([string]$text, [string]$pattern, [string]$insert) {
  $rx = New-Object System.Text.RegularExpressions.Regex($pattern)
  $m = $rx.Match($text)
  if (-not $m.Success) { return $null }
  $nl = "`n"
  if ($text.Contains("`r`n")) { $nl = "`r`n" }
  $indent = $m.Groups[1].Value
  $body = ''
  foreach ($line in ($insert -split "`n")) {
    $l = $line.TrimEnd("`r")
    if ($l -eq '') { $body = $body + $nl }
    else { $body = $body + $indent + $l + $nl }
  }
  return $text.Substring(0, $m.Index) + $body + $text.Substring($m.Index)
}

Say '=================================================='
Say 'AwgChain patch 13 - the chain builder in the interface'
Say ('date   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('client : ' + $Client)
Say ('core   : ' + $Core)
Say '=================================================='

$writer = Join-Path $Core 'conf\writer.go'
$confBuild = Join-Path $Core 'conf\chainbuild.go'
$uiBuild = Join-Path $Client 'ui\chainbuild.go'
$tunnelsPage = Join-Path $Client 'ui\tunnelspage.go'

if ($Revert) {
  Say 'reverting patch 13...'
  Restore-Backup $writer 'conf\writer.go'
  Restore-Backup $tunnelsPage 'ui\tunnelspage.go'
  foreach ($extra in @($confBuild, $uiBuild)) {
    if (Test-Path -LiteralPath $extra) {
      Remove-Item -LiteralPath $extra -Force
      Write-Host ('[OK] removed ' + (Split-Path -Leaf $extra))
    }
  }
  Say 'RESULT=REVERTED'
  Say 'rebuild with: awgchain.bat build'
  exit 0
}

foreach ($needed in @($writer, $tunnelsPage)) {
  if (-not (Test-Path -LiteralPath $needed)) { Bad ($needed + ' was not found') }
}
if ($fails -gt 0) { Say 'RESULT=FAIL the source trees are not where I expected'; exit 1 }

$configGo = Join-Path $Core 'conf\config.go'
$configText = [System.IO.File]::ReadAllText($configGo)
if ($configText -notmatch 'PinEndpointVia') {
  Bad 'conf\config.go has no PinEndpointVia field, so patch 1 is missing. Run: awgchain.bat build'
  Say 'RESULT=FAIL patch 1 first'
  exit 1
}

# ---------------------------------------------------------------- step 1
Say ''
Say 'step 1 of 4: conf\writer.go keeps PinEndpointVia'
$text = [System.IO.File]::ReadAllText($writer)
if ($text -match 'PinEndpointVia') {
  Ok 'writer.go already writes PinEndpointVia'
} else {
  $insert = @'
if len(conf.Interface.PinEndpointVia) > 0 {
	output.WriteString(fmt.Sprintf("PinEndpointVia = %s\n", conf.Interface.PinEndpointVia))
}
'@
  $next = Insert-Before $text '(?m)^([ \t]*)if conf\.Interface\.TableOff \{' $insert
  if ($next -eq $null) {
    Bad 'writer.go: could not find the Table = off block'
  } else {
    Backup-Once $writer
    Write-Text $writer $next
    Ok 'writer.go now saves PinEndpointVia next to Table = off'
  }
}

# ---------------------------------------------------------------- step 2
Say ''
Say 'step 2 of 4: conf\chainbuild.go turns two configs into two hops'
$src = Join-Path $Here 'chainbuild-conf.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('chainbuild-conf.go was not found next to this script: ' + $Here)
} else {
  Copy-Item -LiteralPath $src -Destination $confBuild -Force
  Ok 'conf\chainbuild.go is in place'
}

# ---------------------------------------------------------------- step 3
Say ''
Say 'step 3 of 4: ui\chainbuild.go holds the dialog'
$src = Join-Path $Here 'chainbuild-ui.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('chainbuild-ui.go was not found next to this script: ' + $Here)
} else {
  Copy-Item -LiteralPath $src -Destination $uiBuild -Force
  Ok 'ui\chainbuild.go is in place'
}

# ---------------------------------------------------------------- step 4
Say ''
Say 'step 4 of 4: ui\tunnelspage.go gets the menu entry'
$text = [System.IO.File]::ReadAllText($tunnelsPage)
if ($text -match 'onBuildChain') {
  Ok 'tunnelspage.go already offers the chain builder'
} else {
  $menuInsert = @'
chainAction := walk.NewAction()
chainAction.SetText(l18n.Sprintf("Build a &chain from two configs..."))
chainAction.Triggered().Attach(tp.onBuildChain)
addMenu.Actions().Add(chainAction)

'@
  $contextInsert = @'
chainAction2 := walk.NewAction()
chainAction2.SetText(l18n.Sprintf("Build a &chain from two configs..."))
chainAction2.SetVisible(IsAdmin)
chainAction2.Triggered().Attach(tp.onBuildChain)
contextMenu.Actions().Add(chainAction2)

'@
  $step = Insert-Before $text '(?m)^([ \t]*)addMenuAction := walk\.NewMenuAction\(addMenu\)' $menuInsert
  if ($step -eq $null) {
    Bad 'tunnelspage.go: could not find the Add Tunnel menu'
  } else {
    $step2 = Insert-Before $step '(?m)^([ \t]*)exportAction2 := walk\.NewAction\(\)' $contextInsert
    if ($step2 -eq $null) {
      Bad 'tunnelspage.go: could not find the context menu'
    } else {
      Backup-Once $tunnelsPage
      Write-Text $tunnelsPage $step2
      Ok 'tunnelspage.go: Build a chain from two configs... added to both menus'
    }
  }
}

Say ''
if ($fails -gt 0) {
  Say ('RESULT=FAIL failed steps: ' + $fails)
  exit 1
}
Say 'RESULT=OK'
exit 0
