# AwgChain patch 14 - the chain behaves like a single tunnel
#
#   1. conf\store.go       DeleteName removes the plain .conf too, and does
#                          not complain when a file is already gone
#                          (this is the "cannot delete tunnel" error)
#   2. conf\chainbuild.go   new version: automatic names warpam, warpam1 ...
#   3. ui\chainbuild.go     new version: Russian dialogs, delete and rename
#   4. ui\listview.go       the outer hop is hidden from the tunnel list
#   5. ui\tunnelspage.go    delete and edit go through the chain helpers,
#                          the menu entry gets its Russian label
#
# Patch 13 has to be applied first. Files are backed up once as
# <name>.orig-p14. Undo with -Revert. Re-running is safe.

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
  $b = $path + '.orig-p14'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p14'
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
Say '=== AwgChain patch 14: the chain is one tunnel ==='
Say ('client: ' + $Client)
Say ('core:   ' + $Core)
Say ('here:   ' + $Here)
Say ''

$storeGo = Join-Path $Core 'conf\store.go'
$confSrc = Join-Path $Here 'chainbuild-conf.go'
$confDst = Join-Path $Core 'conf\chainbuild.go'
$uiSrc = Join-Path $Here 'chainbuild-ui.go'
$uiDst = Join-Path $Client 'ui\chainbuild.go'
$listGo = Join-Path $Client 'ui\listview.go'
$pageGo = Join-Path $Client 'ui\tunnelspage.go'

foreach ($p in @($storeGo, $listGo, $pageGo)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Bad ('the source file was not found: ' + $p)
  }
}
if ($fails -gt 0) { Say 'RESULT=FAIL'; exit 1 }

if ($Revert) {
  Say '--- undoing patch 14 ---'
  Restore-Backup $storeGo 'conf\store.go'
  Restore-Backup $listGo 'ui\listview.go'
  Restore-Backup $pageGo 'ui\tunnelspage.go'
  Say 'RESULT=REVERTED'
  Say 'The chain builder from patch 13 stays in place, only the'
  Say 'single-tunnel behaviour is gone. Rebuild the client afterwards.'
  exit 0
}

foreach ($p in @($confSrc, $uiSrc)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Bad ('the file from the pack was not found: ' + $p)
  }
}
if ($fails -gt 0) { Say 'RESULT=FAIL'; exit 1 }

$pageText = [System.IO.File]::ReadAllText($pageGo)
if (-not $pageText.Contains('onBuildChain')) {
  Bad 'patch 13 has not been applied yet: ui\tunnelspage.go has no chain entry. Run: awgchain.bat patch13'
  Say 'RESULT=FAIL'
  exit 1
}

# ---------------------------------------------------------------- 1. store.go
Say '--- 1. conf\store.go: deleting a tunnel removes both config files ---'
$t = [System.IO.File]::ReadAllText($storeGo)
if ($t.Contains('removedAny')) {
  Ok 'store.go already deletes both files'
} else {
  $old = 'return os.Remove(filepath.Join(configFileDir, name+configFileSuffix))'
  $new = @'
removedAny := false
	var lastErr error
	for _, suffix := range []string{configFileSuffix, configFileUnencryptedSuffix} {
		if rmErr := os.Remove(filepath.Join(configFileDir, name+suffix)); rmErr != nil {
			if !os.IsNotExist(rmErr) {
				lastErr = rmErr
			}
		} else {
			removedAny = true
		}
	}
	if lastErr != nil && !removedAny {
		return lastErr
	}
	return nil
'@
  $new = $new.Trim()
  $res = Replace-Once $t $old $new
  if ($res -eq $null) {
    Bad 'conf\store.go: could not find the single line of DeleteName'
  } else {
    Backup-Once $storeGo
    Write-Text $storeGo $res
    Ok 'store.go: DeleteName now removes .conf and .conf.dpapi and tolerates a missing file'
  }
}

# ------------------------------------------------------- 2. conf\chainbuild.go
Say '--- 2. conf\chainbuild.go: automatic names warpam, warpam1, ... ---'
Copy-Item -LiteralPath $confSrc -Destination $confDst -Force
if (Test-Path -LiteralPath $confDst) { Ok 'conf\chainbuild.go is in place' } else { Bad 'could not copy conf\chainbuild.go' }

# --------------------------------------------------------- 3. ui\chainbuild.go
Say '--- 3. ui\chainbuild.go: Russian dialogs, delete and rename helpers ---'
Copy-Item -LiteralPath $uiSrc -Destination $uiDst -Force
if (Test-Path -LiteralPath $uiDst) { Ok 'ui\chainbuild.go is in place' } else { Bad 'could not copy ui\chainbuild.go' }

# ----------------------------------------------------------- 4. ui\listview.go
Say '--- 4. ui\listview.go: the outer hop is hidden from the list ---'
$t = [System.IO.File]::ReadAllText($listGo)
if ($t.Contains('ChainIsHiddenHopName')) {
  Ok 'listview.go already hides the outer hop'
} else {
  $ins = "if conf.ChainIsHiddenHopName(tunnel.Name) {`n`tcontinue`n}"
  $new = Insert-Before $t '(?m)^([ \t]*)newTunnels\[tunnel\] = true[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'ui\listview.go: could not find the line newTunnels[tunnel] = true'
  } else {
    Backup-Once $listGo
    Write-Text $listGo $new
    Ok 'listview.go: tunnels whose name ends with -hop1 are not listed any more'
  }
}

# -------------------------------------------------------- 5. ui\tunnelspage.go
Say '--- 5. ui\tunnelspage.go: delete, edit and the Russian label ---'
$t = [System.IO.File]::ReadAllText($pageGo)
$changed = $false

$oldLabel = 'l18n.Sprintf("Build a &chain from two configs...")'
if ($t.Contains($oldLabel)) {
  Backup-Once $pageGo
  $t = $t.Replace($oldLabel, 'chainMenuText')
  $changed = $true
  Ok 'the menu entry now uses the Russian label from ui\chainbuild.go'
} else {
  Ok 'the menu entry already uses the Russian label'
}

if ($t.Contains('chainDeleteTunnel(tunnel)')) {
  Ok 'deleting already removes the hidden hop as well'
} else {
  $res = Replace-Once $t 'err := tunnel.Delete()' 'err := chainDeleteTunnel(tunnel)'
  if ($res -eq $null) {
    Bad 'ui\tunnelspage.go: could not find the delete call in onDelete'
  } else {
    Backup-Once $pageGo
    $t = $res
    $changed = $true
    Ok 'onDelete: deleting a chain removes both hops'
  }
}

if ($t.Contains('chainBeforeEdit(')) {
  Ok 'editing already keeps the hidden hop in step'
} else {
  $new = Insert-Before $t '(?m)^([ \t]*)tunnel\.Delete\(\)[ \t]*\r?$' 'chainBeforeEdit(tunnel.Name, config)'
  if ($new -eq $null) {
    Bad 'ui\tunnelspage.go: could not find the delete call in onEditTunnel'
  } else {
    Backup-Once $pageGo
    $t = $new
    $changed = $true
    Ok 'onEditTunnel: renaming a chain renames and repins the hidden hop'
  }
}

if ($changed) { Write-Text $pageGo $t }

Say ''
if ($fails -gt 0) {
  Say 'RESULT=FAIL  some pieces did not apply, send me this output'
  exit 1
}
Say 'RESULT=OK'
exit 0
