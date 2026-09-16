param(
  [switch]$Revert,
  [string]$Client = "C:\dev\vpnchain\amneziawg-windows-client",
  [string]$Core   = "C:\dev\vpnchain\amneziawg-windows",
  [string]$Logs   = "C:\vpn\logs"
)

# ASCII only in this file. All Russian strings live in the .go.txt templates.
$ErrorActionPreference = "Stop"

$uiBuild   = Join-Path $Client "ui\chainbuild.go"
$uiRoles   = Join-Path $Client "ui\chainroles.go"
$confBuild = Join-Path $Core   "conf\chainbuild.go"
$confRoles = Join-Path $Core   "conf\chainroles.go"
$tplConf   = Join-Path $PSScriptRoot "p19-conf-chainroles.go.txt"
$tplUi     = Join-Path $PSScriptRoot "p19-ui-chainroles.go.txt"

$utf8 = New-Object System.Text.UTF8Encoding($false)
function ReadText($p)  { return [System.IO.File]::ReadAllText($p, $utf8) }
function WriteText($p, $t) { [System.IO.File]::WriteAllText($p, $t, $utf8) }

function Fail($msg) {
  Write-Host ("[ERROR] " + $msg)
  if (-not (Test-Path $Logs)) { New-Item -ItemType Directory -Path $Logs -Force | Out-Null }
  if (Test-Path $uiBuild)   { Copy-Item $uiBuild   (Join-Path $Logs "dump-ui-chainbuild.go.txt")   -Force }
  if (Test-Path $confBuild) { Copy-Item $confBuild (Join-Path $Logs "dump-conf-chainbuild.go.txt") -Force }
  Write-Host "Sources copied to the logs folder, send them to the chat."
  Write-Host ""
  Write-Host "RESULT=FAIL"
  exit 1
}

Write-Host "=== AwgChain patch 19: explicit hop roles and honest MTU ==="
Write-Host ("client  : " + $Client)
Write-Host ("core    : " + $Core)

if ($Revert) {
  $done = 0
  foreach ($f in @($uiBuild, $confBuild)) {
    $bak = $f + ".orig-p19"
    if (Test-Path $bak) { Copy-Item $bak $f -Force; Remove-Item $bak -Force; $done++ ; Write-Host ("[OK] restored " + $f) }
  }
  foreach ($f in @($uiRoles, $confRoles)) {
    if (Test-Path $f) { Remove-Item $f -Force; Write-Host ("[OK] removed " + $f) }
  }
  Write-Host ""
  if ($done -gt 0) { Write-Host "RESULT=OK" } else { Write-Host "RESULT=FAIL" }
  Write-Host "Next:  awgchain.bat build   then   awgchain.bat install"
  exit 0
}

foreach ($f in @($uiBuild, $confBuild, $tplConf, $tplUi)) {
  if (-not (Test-Path $f)) { Fail ("missing file: " + $f) }
}

# ---- 1. conf\chainroles.go (always rewritten from the template) ----------
WriteText $confRoles (ReadText $tplConf)
Write-Host "[OK] conf\chainroles.go written"

# ---- 2. ui\chainroles.go with import paths taken from ui\chainbuild.go ---
$uiText = ReadText $uiBuild
$confImport = ""
$walkImport = ""
foreach ($m in [regex]::Matches($uiText, '"([^"]+)"')) {
  $p = $m.Groups[1].Value
  if ($p -match '/conf$' -and $confImport -eq "") { $confImport = $p }
  if ($p -match '/walk$' -and $walkImport -eq "") { $walkImport = $p }
}
if ($confImport -eq "") { Fail "could not find the conf import path in ui\chainbuild.go" }
if ($walkImport -eq "") { $walkImport = "github.com/lxn/walk" }
Write-Host ("      conf import: " + $confImport)
Write-Host ("      walk import: " + $walkImport)

$uiRolesText = (ReadText $tplUi).Replace("@CONF_IMPORT@", $confImport).Replace("@WALK_IMPORT@", $walkImport)
WriteText $uiRoles $uiRolesText
Write-Host "[OK] ui\chainroles.go written"

# ---- 3. ui\chainbuild.go: ask instead of guess ---------------------------
if ($uiText -match "chainPickRoles\(") {
  Write-Host "[SKIP] ui\chainbuild.go already calls chainPickRoles"
} else {
  if (-not (Test-Path ($uiBuild + ".orig-p19"))) { Copy-Item $uiBuild ($uiBuild + ".orig-p19") -Force }
  $pattern = '(?s)([ \t]*)([A-Za-z0-9_]+), ([A-Za-z0-9_]+), err := conf\.ChainSortRoles\([^\r\n]*\r?\n(?:[ \t]*if err != nil \{.*?\r?\n[ \t]*\}\r?\n)?'
  $m = [regex]::Match($uiText, $pattern)
  if (-not $m.Success) { Fail "could not find the ChainSortRoles call in ui\chainbuild.go" }
  $ind = $m.Groups[1].Value
  $v1  = $m.Groups[2].Value
  $v2  = $m.Groups[3].Value
  $new = $ind + $v1 + ", " + $v2 + ", ok := chainPickRoles(tp.Form(), configs)" + "`n" +
         $ind + "if !ok {" + "`n" +
         $ind + "`treturn" + "`n" +
         $ind + "}" + "`n"
  $uiText = $uiText.Remove($m.Index, $m.Length).Insert($m.Index, $new)
  WriteText $uiBuild $uiText
  Write-Host "[OK] the window now asks which config is the outer hop"
}

# ---- 4. conf\chainbuild.go: MTU text from the constants -------------------
$confText = ReadText $confBuild
if ($confText -match "strconv\.Itoa\(ChainHop1MTU\)") {
  Write-Host "[SKIP] conf\chainbuild.go already prints the MTU constants"
} else {
  if (-not (Test-Path ($confBuild + ".orig-p19"))) { Copy-Item $confBuild ($confBuild + ".orig-p19") -Force }
  $before = $confText
  $confText = [regex]::Replace($confText, '"([^"\r\n]*?)MTU 1420([^"\r\n]*?)"', '"$1MTU " + strconv.Itoa(ChainHop1MTU) + "$2"')
  $confText = [regex]::Replace($confText, '"([^"\r\n]*?)MTU 1360([^"\r\n]*?)"', '"$1MTU " + strconv.Itoa(ChainHop2MTU) + "$2"')
  if ($confText -eq $before) { Fail "no hard coded MTU text found in conf\chainbuild.go" }
  $confText = [regex]::Replace($confText, '\s\+\s""\s*\+', ' +')
  $confText = [regex]::Replace($confText, '\s\+\s""(\s*\r?\n)', '$1')
  if ($confText -notmatch '\"strconv\"') {
    $mi = [regex]::Match($confText, '(?s)import \(\r?\n')
    if ($mi.Success) {
      $confText = $confText.Insert($mi.Index + $mi.Length, "`t`"strconv`"`n")
    } else {
      $mp = [regex]::Match($confText, 'package conf\r?\n')
      if (-not $mp.Success) { Fail "could not add the strconv import" }
      $confText = $confText.Insert($mp.Index + $mp.Length, "`nimport `"strconv`"`n")
    }
    Write-Host "[OK] strconv import added"
  }
  WriteText $confBuild $confText
  Write-Host "[OK] the summary prints the real MTU constants"
}

Write-Host ""
Write-Host "RESULT=OK"
Write-Host "Next:  awgchain.bat build   then   awgchain.bat install"
