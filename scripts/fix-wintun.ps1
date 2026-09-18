param([switch]$Apply,[switch]$Download)

$ErrorActionPreference = 'Continue'

function Say($m)  { Write-Host $m }
function Ok($m)   { Write-Host ("[OK] " + $m) }
function Bad($m)  { Write-Host ("[!!] " + $m) }

$binDir = 'C:\Program Files\AwgChain\bin'
$target = Join-Path $binDir 'wintun.dll'
$goodSize = 427552

Say '=== wintun.dll doctor ==='

function Get-DllInfo([string]$path) {
    $res = New-Object psobject -Property @{ Path = $path; Size = 0; Machine = ''; Good = $false; Note = '' }
    try {
        $fi = Get-Item -LiteralPath $path -ErrorAction Stop
        $res.Size = $fi.Length
        if ($fi.Length -lt 4096) { $res.Note = 'too small / truncated'; return $res }
        $fs = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $buf = New-Object byte[] 1024
        $read = $fs.Read($buf,0,1024)
        $fs.Close()
        if ($read -lt 64) { $res.Note = 'header unreadable'; return $res }
        if ($buf[0] -ne 0x4D -or $buf[1] -ne 0x5A) { $res.Note = 'no MZ header, not a DLL'; return $res }
        $peOff = [BitConverter]::ToInt32($buf,60)
        if ($peOff -le 0 -or ($peOff + 6) -ge $read) { $res.Note = 'bad PE offset'; return $res }
        if ($buf[$peOff] -ne 0x50 -or $buf[$peOff+1] -ne 0x45) { $res.Note = 'no PE header'; return $res }
        $machine = [BitConverter]::ToUInt16($buf,($peOff+4))
        $res.Machine = ('0x{0:x}' -f $machine)
        if ($machine -eq 0x8664) { $res.Good = $true; $res.Note = 'x64, looks valid' }
        elseif ($machine -eq 0x14c) { $res.Note = 'x86 build, wrong bitness' }
        elseif ($machine -eq 0xaa64) { $res.Note = 'arm64 build, wrong platform' }
        else { $res.Note = 'unknown machine type' }
    } catch {
        $res.Note = 'error: ' + $_.Exception.Message
    }
    return $res
}

Say ''
Say '--- the file the tunnel service loads ---'
if (Test-Path -LiteralPath $target) {
    $cur = Get-DllInfo $target
    Say (("{0,10}  {1,-8}  {2}") -f $cur.Size, $cur.Machine, $cur.Note)
    Say $cur.Path
    if ($cur.Good) { Ok 'the installed wintun.dll is a valid x64 DLL' } else { Bad 'the installed wintun.dll is broken, this is why the tunnel cannot start' }
} else {
    $cur = $null
    Bad ('missing: ' + $target)
}

Say ''
Say '--- every other copy on the machine ---'
$roots = @('C:\Program Files\AwgChain','C:\vpn','C:\dev\vpnchain','C:\Program Files\WireGuard','C:\Program Files\AmneziaVPN','C:\Program Files (x86)\AmneziaVPN')
$found = @()
foreach ($r in $roots) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    $items = Get-ChildItem -LiteralPath $r -Recurse -Filter 'wintun.dll' -File -Force -ErrorAction SilentlyContinue
    foreach ($it in $items) {
        if ($it.FullName -eq $target) { continue }
        $info = Get-DllInfo $it.FullName
        $found += $info
        Say (("{0,10}  {1,-8}  {2,-24}  {3}") -f $info.Size, $info.Machine, $info.Note, $info.Path)
    }
}
if ($found.Count -eq 0) { Say '(no other copy found)' }

Say ''
Say '--- who copies wintun.dll in the scripts ---'
$scripts = Get-ChildItem -LiteralPath 'C:\vpn' -Filter '*.bat' -File -ErrorAction SilentlyContinue
foreach ($s in $scripts) {
    $hits = Select-String -LiteralPath $s.FullName -Pattern 'wintun' -SimpleMatch -ErrorAction SilentlyContinue
    foreach ($h in $hits) {
        Say (("{0}:{1}: {2}") -f $s.Name, $h.LineNumber, $h.Line.Trim())
    }
}

$best = $null
foreach ($f in $found) {
    if (-not $f.Good) { continue }
    if ($f.Size -eq $goodSize) { $best = $f; break }
    if ($best -eq $null) { $best = $f }
}

if ($Download) {
    Say ''
    Say '--- downloading a fresh Wintun 0.14.1 from wintun.net ---'
    $tmp = Join-Path $env:TEMP 'wintun-dl'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'wintun.zip'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://www.wintun.net/builds/wintun-0.14.1.zip' -OutFile $zip -UseBasicParsing
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $dl = Join-Path $tmp 'wintun\bin\amd64\wintun.dll'
        if (Test-Path -LiteralPath $dl) {
            $info = Get-DllInfo $dl
            Say (("{0,10}  {1,-8}  {2,-24}  {3}") -f $info.Size, $info.Machine, $info.Note, $info.Path)
            if ($info.Good) { $best = $info; Ok 'downloaded copy will be used' }
        } else {
            Bad 'the archive does not contain bin\amd64\wintun.dll'
        }
    } catch {
        Bad ('download failed: ' + $_.Exception.Message)
    }
}

Say ''
if ($best -eq $null) {
    Bad 'no healthy x64 copy of wintun.dll was found on this machine'
    Say 'run the same script with -Download to pull a fresh one from wintun.net'
    Say 'RESULT=FAIL reason=nosource'
    exit 1
}

Say ('source to use: ' + $best.Path + '  (' + $best.Size + ' bytes, ' + $best.Machine + ')')

if (-not $Apply) {
    Say ''
    Say 'this was a dry run, nothing was changed'
    Say 'run again with -Apply to put the healthy copy in place'
    Say 'RESULT=OK'
    exit 0
}

Say ''
Say '--- stopping the services that hold the DLL ---'
$svcs = Get-Service -Name 'AwgChainTunnel$*' -ErrorAction SilentlyContinue
foreach ($sv in $svcs) {
    Say ('stopping ' + $sv.Name)
    Stop-Service -Name $sv.Name -Force -ErrorAction SilentlyContinue
}
$mgr = Get-Service -Name 'AwgChainManager' -ErrorAction SilentlyContinue
if ($mgr -ne $null) {
    Say 'stopping AwgChainManager'
    Stop-Service -Name 'AwgChainManager' -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

if (Test-Path -LiteralPath $target) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = $target + '.bad-' + $stamp
    try {
        Move-Item -LiteralPath $target -Destination $bak -Force -ErrorAction Stop
        Ok ('the broken file was moved to ' + $bak)
    } catch {
        Bad ('cannot move the broken file: ' + $_.Exception.Message)
        Say 'RESULT=FAIL reason=locked'
        exit 1
    }
}

try {
    Copy-Item -LiteralPath $best.Path -Destination $target -Force -ErrorAction Stop
} catch {
    Bad ('copy failed: ' + $_.Exception.Message)
    Say 'RESULT=FAIL reason=copy'
    exit 1
}

$check = Get-DllInfo $target
Say (("{0,10}  {1,-8}  {2}") -f $check.Size, $check.Machine, $check.Note)
if (-not $check.Good) {
    Bad 'the copy in place is still not a valid x64 DLL'
    Say 'RESULT=FAIL reason=stillbad'
    exit 1
}

Ok 'wintun.dll is healthy again'
Say 'next: C:\vpn\awgchain.bat up'
Say 'RESULT=OK'
exit 0
