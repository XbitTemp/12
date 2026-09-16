# AwgChain patch 7 - plain-text configs for chain hops
#
# The manager encrypts every .conf it finds into .conf.dpapi and deletes the
# original. Our tunnel services point at the plain path, so that silently
# breaks the chain the next time a service is started. Five small edits in the
# core fork make the plain file a first-class citizen for chain hops only:
#
#   1. conf\chainconf.go          new file: what a chain hop is on disk
#   2. conf\store.go              LoadFromName prefers the plain hop file
#   3. conf\store.go              ListConfigNames also lists plain configs
#   4. conf\store.go              Save keeps a chain hop in plain text
#   5. conf\store.go              Path returns the plain path of a chain hop
#   6. conf\migration_windows.go  the DPAPI sweep skips chain hops
#
# Ordinary tunnels keep the upstream behaviour exactly. Every touched file is
# backed up once as <name>.orig-p7. Undo with -Revert. Re-running is safe.

param(
  [string]$Core = 'C:\dev\vpnchain\amneziawg-windows',
  [string]$Here = '',
  [switch]$Revert
)

$ErrorActionPreference = 'Continue'

# A trailing backslash inside a quoted cmd argument escapes the closing quote.
$Here = ('' + $Here).Trim().Trim('"').Trim().TrimEnd('\')
if ($Here -eq '') { $Here = Split-Path -Parent $MyInvocation.MyCommand.Path }
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
  $b = $path + '.orig-p7'
  if (-not (Test-Path -LiteralPath $b)) {
    Copy-Item -LiteralPath $path -Destination $b -Force
    Write-Host ('  a copy of the original is kept as ' + (Split-Path -Leaf $b))
  }
}

function Restore-Backup([string]$path, [string]$label) {
  $b = $path + '.orig-p7'
  if (Test-Path -LiteralPath $b) {
    Copy-Item -LiteralPath $b -Destination $path -Force
    Remove-Item -LiteralPath $b -Force
    Write-Host ('[OK] ' + $label + ' was restored from the backup')
  } else {
    Write-Host ('  no backup for ' + $label + ', leaving it alone')
  }
}

# Insert $insert immediately before the first line matching $pattern.
# Returns the new text, or $null when the anchor was not found.
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
Say 'AwgChain patch 7 - plain-text configs for chain hops'
Say ('date : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ('core : ' + $Core)
Say '=================================================='

$storeGo = Join-Path $Core 'conf\store.go'
$migGo   = Join-Path $Core 'conf\migration_windows.go'
$chainGo = Join-Path $Core 'conf\chainconf.go'
$confGo  = Join-Path $Core 'conf\config.go'

foreach ($p in @($storeGo, $migGo, $confGo)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Bad ('source file not found: ' + $p)
    Say 'RESULT=FAIL nothing was changed'
    exit 1
  }
}

# ---------------------------------------------------------------- revert ---
if ($Revert) {
  Say '--- revert ---'
  Restore-Backup $storeGo 'conf\store.go'
  Restore-Backup $migGo   'conf\migration_windows.go'
  if (Test-Path -LiteralPath $chainGo) {
    Remove-Item -LiteralPath $chainGo -Force
    Ok 'conf\chainconf.go was removed'
  }
  Say '=================================================='
  Say 'RESULT=REVERTED'
  Say 'Rebuild and reinstall to put the old behaviour back.'
  exit 0
}

# --------------------------------------------- 0. the PinEndpointVia field ---
Say '--- 0. the chain field in conf ---'
$cf = Get-Content -LiteralPath $confGo -Raw
if ($cf -match 'PinEndpointVia') {
  foreach ($line in (Get-Content -LiteralPath $confGo)) {
    if ($line -match 'PinEndpointVia') { Say ('  found: ' + $line.Trim()) }
  }
  Ok 'patch 1 is in place, a chain hop can be recognised'
} else {
  Bad 'conf\config.go has no PinEndpointVia field - apply patch 1 first'
  Say 'RESULT=FAIL nothing was changed'
  exit 1
}

# --------------------------------------------------------- 1. chainconf.go ---
Say '--- 1. conf\chainconf.go ---'
$src = Join-Path $Here 'chainconf.go'
if (-not (Test-Path -LiteralPath $src)) {
  Bad ('chainconf.go was not found next to this script: ' + $src)
} else {
  Copy-Item -LiteralPath $src -Destination $chainGo -Force
  Ok 'chainconf.go was copied into conf\'
}

# ------------------------------------------------------- 2. LoadFromName ---
Say '--- 2. conf\store.go: LoadFromName prefers the plain hop file ---'
$t = Get-Content -LiteralPath $storeGo -Raw
if ($t -match 'chainPlainPath\(configFileDir, name\)') {
  Ok 'LoadFromName already knows about plain chain hops'
} else {
  $ins = @'
if plain, ok := chainPlainPath(configFileDir, name); ok {
	// AwgChain: a chain hop is owned by the chain tooling and lives in plain
	// text. Prefer it over any stale encrypted copy left by an earlier sweep.
	return LoadFromPath(plain)
}
if _, err := os.Stat(filepath.Join(configFileDir, name+configFileSuffix)); err != nil {
	plainPath := filepath.Join(configFileDir, name+configFileUnencryptedSuffix)
	if _, err := os.Stat(plainPath); err == nil {
		return LoadFromPath(plainPath)
	}
}
'@
  $new = Insert-Before $t '(?m)^([ \t]*)return LoadFromPath\(filepath\.Join\(configFileDir, name\+configFileSuffix\)\)[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'the LoadFromPath anchor was not found in LoadFromName()'
  } else {
    Backup-Once $storeGo
    Write-Text $storeGo $new
    $t = $new
    Ok 'LoadFromName now reads the plain file of a chain hop'
  }
}

# ----------------------------------------------------- 3. ListConfigNames ---
Say '--- 3. conf\store.go: ListConfigNames lists plain configs ---'
if ($t -match 'plainConfigName\(configFileDir, file\)') {
  Ok 'ListConfigNames already lists plain configs'
} else {
  $ins = @'
if plainName, ok := plainConfigName(configFileDir, file); ok {
	// AwgChain: a plain config with no encrypted counterpart is a real tunnel
	// too, so the interface must see it in the list.
	configs[i] = plainName
	i++
	continue
}
'@
  $new = Insert-Before $t '(?m)^([ \t]*)name := filepath\.Base\(file\.Name\(\)\)[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'the filepath.Base(file.Name()) anchor was not found in ListConfigNames()'
  } else {
    Backup-Once $storeGo
    Write-Text $storeGo $new
    $t = $new
    Ok 'the interface will list plain configs as ordinary tunnels'
  }
}

# ---------------------------------------------------------------- 4. Save ---
Say '--- 4. conf\store.go: Save keeps a chain hop in plain text ---'
if ($t -match 'a chain hop stays in plain text') {
  Ok 'Save already writes chain hops in plain text'
} else {
  $ins = @'
if config.Interface.PinEndpointVia != "" {
	// AwgChain: a chain hop stays in plain text, so that the interface, the
	// batch tooling, the watchdog and the tunnel services all read one file.
	plainName := filepath.Join(configFileDir, config.Name+configFileUnencryptedSuffix)
	return writeLockedDownFile(plainName, overwrite, []byte(config.ToWgQuick()))
}
'@
  $new = Insert-Before $t '(?m)^([ \t]*)filename := filepath\.Join\(configFileDir, config\.Name\+configFileSuffix\)[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'the filename := anchor was not found in Save()'
  } else {
    Backup-Once $storeGo
    Write-Text $storeGo $new
    $t = $new
    Ok 'editing a hop in the interface no longer forks the config in two'
  }
}

# ---------------------------------------------------------------- 5. Path ---
Say '--- 5. conf\store.go: Path returns the plain path of a chain hop ---'
if ($t -match 'chainPlainPath\(configFileDir, config\.Name\)') {
  Ok 'Path already returns the plain path for chain hops'
} else {
  $ins = @'
if plain, ok := chainPlainPath(configFileDir, config.Name); ok {
	// AwgChain: this is the path the tunnel service will be pointed at.
	return plain, nil
}
'@
  $new = Insert-Before $t '(?m)^([ \t]*)return filepath\.Join\(configFileDir, config\.Name\+configFileSuffix\), nil[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'the return filepath.Join anchor was not found in Path()'
  } else {
    Backup-Once $storeGo
    Write-Text $storeGo $new
    Ok 'activating a hop from the interface points at the plain file'
  }
}

# ----------------------------------------------------------- 6. migration ---
Say '--- 6. conf\migration_windows.go: skip chain hops ---'
$t = Get-Content -LiteralPath $migGo -Raw
if ($t -match 'fileIsChainHop\(path\)') {
  Ok 'the DPAPI sweep already leaves chain hops alone'
} else {
  $ins = @'
if fileIsChainHop(path) {
	// AwgChain: this file is edited outside the manager and the tunnel service
	// points straight at it. Encrypting it here would delete it under our feet.
	log.Printf("Leaving chain hop %#q in plain text", path)
	continue
}
'@
  $new = Insert-Before $t '(?m)^([ \t]*)var bytes \[\]byte[ \t]*\r?$' $ins
  if ($new -eq $null) {
    Bad 'the var bytes []byte anchor was not found in migrateUnencryptedConfigs()'
  } else {
    Backup-Once $migGo
    Write-Text $migGo $new
    Ok 'chain hops survive the DPAPI sweep untouched'
  }
}

Say '=================================================='
if ($fails -eq 0) {
  Say 'RESULT=OK'
  exit 0
} else {
  Say ('RESULT=FAIL failed steps: ' + $fails)
  exit 1
}
