# AwgChain patch 15 - both halves of the chain in one editor window
#
#   1. ui\chainbuild.go          new version: the combined editor helpers
#   2. ui\editdialog.go          the WARP hop is shown under the config as
#                                '#!' lines and saved together with it
#   3. ui\syntax\highlighter.go  PinEndpointVia is a known key, so the Save
#                                button no longer greys out
#
# Patch 14 has to be applied first. Files are backed up once as
# <name>.orig-p15. Undo with -Revert. Re-running is safe.

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
  $b = $path + '.orig-p15'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p15'
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

function Replace-Once([string]$text, [string]$old, [string]$new) {
  $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
  if ($count -ne 1) { return $null }
  return $text.Replace($old, $new)
}

Say ''
Say '=== AwgChain patch 15: both halves of the chain in one editor ==='
Say ('client: ' + $Client)
Say ('core:   ' + $Core)
Say ('here:   ' + $Here)
Say ''

$uiSrc = Join-Path $Here 'chainbuild-ui.go'
$uiDst = Join-Path $Client 'ui\chainbuild.go'
$editGo = Join-Path $Client 'ui\editdialog.go'
$hiGo = Join-Path $Client 'ui\syntax\highlighter.go'

foreach ($p in @($editGo, $hiGo)) {
  if (-not (Test-Path -LiteralPath $p)) { Bad ('the source file was not found: ' + $p) }
}
if ($fails -gt 0) { Say 'RESULT=FAIL'; exit 1 }

if ($Revert) {
  Say '--- undoing patch 15 ---'
  Restore-Backup $editGo 'ui\editdialog.go'
  Restore-Backup $hiGo 'ui\syntax\highlighter.go'
  Say 'RESULT=REVERTED'
  Say 'Run awgchain.bat patch14 afterwards to put the matching ui\chainbuild.go back.'
  exit 0
}

if (-not (Test-Path -LiteralPath $uiSrc)) {
  Bad ('the file from the pack was not found: ' + $uiSrc)
  Say 'RESULT=FAIL'
  exit 1
}

$pageGo = Join-Path $Client 'ui\tunnelspage.go'
$pageText = [System.IO.File]::ReadAllText($pageGo)
if (-not $pageText.Contains('chainBeforeEdit')) {
  Bad 'patch 14 has not been applied yet. Run: awgchain.bat patch14'
  Say 'RESULT=FAIL'
  exit 1
}

# ------------------------------------------------------- 1. ui\chainbuild.go
Say '--- 1. ui\chainbuild.go: the combined editor helpers ---'
Copy-Item -LiteralPath $uiSrc -Destination $uiDst -Force
if (Test-Path -LiteralPath $uiDst) { Ok 'ui\chainbuild.go is in place' } else { Bad 'could not copy ui\chainbuild.go' }

# ------------------------------------------------------- 2. ui\editdialog.go
Say '--- 2. ui\editdialog.go: show and save both halves ---'
$t = [System.IO.File]::ReadAllText($editGo)
if ($t.Contains('chainEditorText')) {
  Ok 'editdialog.go already shows both halves'
} else {
  Backup-Once $editGo
  $step = 0

  $res = Replace-Once $t 'dlg.syntaxEdit.SetText(dlg.config.ToWgQuick())' 'dlg.syntaxEdit.SetText(chainEditorText(tunnel, &dlg.config))'
  if ($res -eq $null) { Bad 'editdialog.go: could not find the line that fills the editor' } else { $t = $res; $step = $step + 1 }

  $res = Replace-Once $t 'dlg.syntaxEdit.SetText(cfg.ToWgQuick())' 'dlg.syntaxEdit.SetText(chainKeepHop1(dlg.syntaxEdit.Text(), cfg.ToWgQuick()))'
  if ($res -eq $null) { Bad 'editdialog.go: could not find the kill-switch checkbox rewrite' } else { $t = $res; $step = $step + 1 }

  $oldSave = 'cfg, err := conf.FromWgQuick(dlg.syntaxEdit.Text(), newName)'
  $newSave = 'mainText, hopText := chainSplitEditorText(dlg.syntaxEdit.Text())' + "`n" +
    "`tif chainErr := chainStashHop1(hopText, newName); chainErr != nil {" + "`n" +
    "`t`tshowErrorCustom(dlg, chainTitle, chainHopErrorText+chainErr.Error())" + "`n" +
    "`t`treturn" + "`n" +
    "`t}" + "`n" +
    "`tcfg, err := conf.FromWgQuick(mainText, newName)"
  $res = Replace-Once $t $oldSave $newSave
  if ($res -eq $null) { Bad 'editdialog.go: could not find the save handler' } else { $t = $res; $step = $step + 1 }

  if ($step -eq 3) {
    Write-Text $editGo $t
    Ok 'editdialog.go: the WARP half is shown below the config and saved with it'
  }
}

# ------------------------------------------------ 3. ui\syntax\highlighter.go
Say '--- 3. ui\syntax\highlighter.go: PinEndpointVia is a known key ---'
$t = [System.IO.File]::ReadAllText($hiGo)
if ($t.Contains('fieldPinEndpointVia')) {
  Ok 'the highlighter already knows PinEndpointVia'
} else {
  $step = 0
  $res = Insert-Before $t '(?m)^([ \t]*)fieldPeerSection[ \t]*\r?$' 'fieldPinEndpointVia'
  if ($res -eq $null) { Bad 'highlighter.go: could not find the field list' } else { $t = $res; $step = $step + 1 }

  $ins = 'case s.isCaselessSame("PinEndpointVia"):' + "`n" + "`treturn fieldPinEndpointVia"
  $res = Insert-Before $t '(?m)^([ \t]*)case s\.isCaselessSame\("DisableCookies"\):[ \t]*\r?$' $ins
  if ($res -eq $null) { Bad 'highlighter.go: could not find the key table' } else { $t = $res; $step = $step + 1 }

  $ins = 'case fieldPinEndpointVia:' + "`n" + "`thsa.append(parent.s, s, highlightCmd)"
  $res = Insert-Before $t '(?m)^([ \t]*)case fieldDisableCookies:[ \t]*\r?$' $ins
  if ($res -eq $null) { Bad 'highlighter.go: could not find the value table' } else { $t = $res; $step = $step + 1 }

  if ($step -eq 3) {
    Backup-Once $hiGo
    Write-Text $hiGo $t
    Ok 'highlighter.go: PinEndpointVia is no longer an error, so Save stays clickable'
  }
}

Say ''
if ($fails -gt 0) {
  Say 'RESULT=FAIL  some pieces did not apply, send me this output'
  exit 1
}
Say 'RESULT=OK'
exit 0
