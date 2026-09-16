param([switch]$Revert,[string]$Src = 'C:\vpn\p45-chainpinwait.go.txt')

$ErrorActionPreference = 'Continue'
$q = [char]34
$tab = [char]9

function Say($t) { Write-Host $t }
function Ok($t)  { Write-Host ('[OK] ' + $t) }
function Bad($t) { Write-Host ('[!!] ' + $t) }

$roots = @('C:\dev\vpnchain\amneziawg-windows-client','C:\dev\vpnchain\amneziawg-windows')
$tun = ''
foreach ($r in $roots) {
  $probe = Join-Path $r 'tunnel\pinendpoint.go'
  if (Test-Path $probe) { $tun = Join-Path $r 'tunnel'; break }
}
if ($tun -eq '') { Bad 'tunnel folder with pinendpoint.go not found'; Write-Host 'RESULT=FAIL reason=notunnel'; exit 1 }
Say ('tunnel folder   : ' + $tun)

$pin   = Join-Path $tun 'pinendpoint.go'
$watch = Join-Path $tun 'interfacewatcher.go'
$route = Join-Path $tun 'pinroute.go'
$new   = Join-Path $tun 'chainpinwait.go'

if ($Revert) {
  foreach ($f in @($pin,$watch,$route)) {
    $b = $f + '.orig-p45'
    if (Test-Path $b) { Copy-Item $b $f -Force; Ok ('restored: ' + $f) }
  }
  if (Test-Path $new) { Remove-Item $new -Force; Ok ('removed: ' + $new) }
  Write-Host 'RESULT=REVERTED'
  exit 0
}

foreach ($f in @($pin,$watch,$route)) {
  if (-not (Test-Path $f)) { Bad ('missing: ' + $f); Write-Host 'RESULT=FAIL reason=missing'; exit 1 }
}
if (-not (Test-Path $Src)) { Bad ('missing template: ' + $Src); Write-Host 'RESULT=FAIL reason=notemplate'; exit 1 }

$watchText = [System.IO.File]::ReadAllText($watch)
if ((Test-Path $new) -and ($watchText -match 'chainIsPinNotReady')) {
  Ok 'patch 26 is already in place'
  Write-Host 'RESULT=OK'
  exit 0
}

function Patch-Line([string]$Path, [string]$Find, [string[]]$NewLines) {
  $text = [System.IO.File]::ReadAllText($Path)
  $lines = $text -split "`r`n|`n"
  $out = New-Object System.Collections.Generic.List[string]
  $hit = 0
  foreach ($l in $lines) {
    if (($hit -eq 0) -and $l.Contains($Find)) {
      $indent = ''
      $m = [regex]::Match($l, '^[\s]*')
      if ($m.Success) { $indent = $m.Value }
      foreach ($n in $NewLines) { $out.Add($indent + $n) }
      $hit = 1
    } else {
      $out.Add($l)
    }
  }
  if ($hit -eq 0) { return $false }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, ($out -join "`n"), $enc)
  return $true
}

foreach ($f in @($pin,$watch,$route)) {
  $b = $f + '.orig-p45'
  if (-not (Test-Path $b)) { Copy-Item $f $b -Force; Say ('backup          : ' + $b) }
}

$fail = 0

$a1 = 'return nil, chainPinNotReady(fmt.Errorf(' + $q + 'pinned interface %q not found' + $q + ', name))'
if (Patch-Line $pin 'pinned interface %q not found' @($a1)) { Ok 'pinendpoint.go: missing adapter is now a temporary condition' } else { Bad 'pinendpoint.go: anchor 1 not found'; $fail = 1 }

$a2 = 'return chainPinNotReady(fmt.Errorf(' + $q + 'pinned interface %q is not up (oper status %d)' + $q + ', pinVia, iface.OperStatus))'
if (Patch-Line $pin 'is not up (oper status %d)' @($a2)) { Ok 'pinendpoint.go: adapter that is not up yet is now a temporary condition' } else { Bad 'pinendpoint.go: anchor 2 not found'; $fail = 1 }

$a3 = 'return chainPinNotReady(fmt.Errorf(' + $q + 'pinned interface %q has no index for this address family' + $q + ', pinVia))'
if (Patch-Line $pin 'has no index for this address family' @($a3)) { Ok 'pinendpoint.go: missing address family index is now a temporary condition' } else { Bad 'pinendpoint.go: anchor 3 not found'; $fail = 1 }

$b1 = @(
  'if chainIsPinNotReady(err) {',
  ($tab + 'iw.chainRetrySetup(family, err)'),
  ($tab + 'return'),
  '}',
  'iw.errors <- interfaceWatcherError{services.ErrorBindSocketsToDefaultRoutes, err}'
)
if (Patch-Line $watch 'iw.errors <- interfaceWatcherError{services.ErrorBindSocketsToDefaultRoutes, err}' $b1) { Ok 'interfacewatcher.go: the tunnel waits for the hop underneath instead of stopping' } else { Bad 'interfacewatcher.go: anchor not found'; $fail = 1 }

$c1 = @(
  'if add {',
  ($tab + 'chainPinRoutesLater(config, err)'),
  '} else {',
  ($tab + 'log.Printf(' + $q + 'Chain pin route: %v' + $q + ', err)'),
  '}'
)
$c1find = 'log.Printf(' + $q + 'Chain pin route: %v' + $q + ', err)'
if (Patch-Line $route $c1find $c1) { Ok 'pinroute.go: the host route is pinned as soon as the hop underneath is here' } else { Bad 'pinroute.go: anchor not found'; $fail = 1 }

$srcText = [System.IO.File]::ReadAllText($Src)
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($new, ($srcText -replace "`r`n", "`n"), $enc)
if (Test-Path $new) { Ok ('new file        : ' + $new) } else { Bad 'could not write chainpinwait.go'; $fail = 1 }

if ($fail -eq 1) { Write-Host 'RESULT=FAIL reason=anchor'; exit 1 }
Write-Host 'RESULT=OK'
exit 0
