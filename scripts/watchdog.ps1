param(
  [int]$Interval = 10,
  [int]$Duration = 0,
  [int]$MaxRecoveries = 0,
  [string]$Hop1 = 'hop1-warp',
  [string]$Hop2 = 'hop2-amnezia',
  [string]$Bin = 'C:\Program Files\AwgChain\bin',
  [string]$Data = 'C:\Program Files\AwgChain\Data',
  [string]$LogDir = '',
  [int]$ProbePort = 443,
  [string]$ProbeHost = '1.1.1.1',
  [ValidateSet('auto', 'handshake', 'tcp')]
  [string]$Probe = 'auto',
  [int]$HandshakeMaxAge = 180,
  [int]$FailsBeforeRecovery = 2,
  [switch]$WithLock,
  [switch]$NoLock,
  [switch]$Once,
  [switch]$StopAfterRecovery,
  [switch]$NoColdStart
)

$ErrorActionPreference = 'Continue'

function Clean-Path([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return '' }
  $p = $p.Trim().Trim('"')
  while ($p.EndsWith('\')) { $p = $p.Substring(0, $p.Length - 1) }
  return $p
}

$Bin = Clean-Path $Bin
$Data = Clean-Path $Data
$LogDir = Clean-Path $LogDir
if ([string]::IsNullOrWhiteSpace($LogDir)) { $LogDir = Join-Path $PSScriptRoot 'logs' }
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$logFile = Join-Path $LogDir 'watchdog-log.txt'
$stopFile = Join-Path $LogDir 'watchdog.stop'
$stateFile = Join-Path $LogDir 'watchdog-state.txt'

function Say([string]$msg) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $msg
  # v4: Write-Host, not Write-Output. Inside functions that return $true/$false
  # the pipeline output was swallowed by the return value, so the repair lines
  # never reached the console log.
  Write-Host $line
  try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch { }
}

function Get-ConfValue([string]$file, [string]$key) {
  if (-not (Test-Path -LiteralPath $file)) { return '' }
  foreach ($line in Get-Content -LiteralPath $file) {
    $t = $line.Trim()
    if ($t.StartsWith('#') -or $t.StartsWith(';')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    if ($t.Substring(0, $i).Trim() -ieq $key) { return $t.Substring($i + 1).Trim() }
  }
  return ''
}

function Resolve-Host([string]$h) {
  $parsed = [System.Net.IPAddress]::Any
  if ([System.Net.IPAddress]::TryParse($h, [ref]$parsed)) { return $h }
  try {
    $a = [System.Net.Dns]::GetHostAddresses($h) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
    if ($a) { return $a.IPAddressToString }
  } catch { }
  return ''
}

function Split-Endpoint([string]$ep) {
  $h = $ep
  $port = ''
  $i = $ep.LastIndexOf(':')
  if ($i -gt 0) { $h = $ep.Substring(0, $i); $port = $ep.Substring($i + 1) }
  return @{ Host = (Resolve-Host ($h.Trim('[', ']'))); Port = $port }
}

function Svc-Name([string]$tunnel) { return ('AwgChainTunnel$' + $tunnel) }

function Svc-State([string]$name) {
  $s = Get-Service -Name $name -ErrorAction SilentlyContinue
  if (-not $s) { return 'MISSING' }
  return [string]$s.Status
}

function Svc-Ensure([string]$tunnel) {
  $name = Svc-Name $tunnel
  if ((Svc-State $name) -ne 'MISSING') { return $true }
  $exe = Join-Path $Bin 'awgchain.exe'
  $conf = Join-Path $Data ('Configurations\' + $tunnel + '.conf')
  if (-not (Test-Path -LiteralPath $exe)) { Say ('  cannot create service, missing ' + $exe); return $false }
  if (-not (Test-Path -LiteralPath $conf)) { Say ('  cannot create service, missing ' + $conf); return $false }
  Say ('  creating service ' + $name)
  $cmd = 'sc create "' + $name + '" binPath= "\"' + $exe + '\" /tunnelservice \"' + $conf + '\"" start= demand depend= Nsi/TcpIp'
  cmd /c $cmd | Out-Null
  cmd /c ('sc sidtype "' + $name + '" unrestricted') | Out-Null
  return ((Svc-State $name) -ne 'MISSING')
}

function Svc-Stop([string]$tunnel, [int]$waitSec = 20) {
  $name = Svc-Name $tunnel
  $st = Svc-State $name
  if ($st -eq 'MISSING') { return }
  if ($st -ne 'Stopped') {
    Say ('  stopping ' + $name)
    cmd /c ('sc stop "' + $name + '"') | Out-Null
  }
  for ($i = 0; $i -lt $waitSec; $i++) {
    if ((Svc-State $name) -in @('Stopped', 'MISSING')) { return }
    Start-Sleep -Seconds 1
  }
  Say ('  ' + $name + ' did not stop in time, state ' + (Svc-State $name))
}

function Iface-Up([string]$alias) {
  $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $alias -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $ip) { return $false }
  $nic = Get-NetAdapter -InterfaceAlias $alias -ErrorAction SilentlyContinue
  if (-not $nic) { return $false }
  return ($nic.Status -eq 'Up')
}

function Iface-Index([string]$alias) {
  $nic = Get-NetAdapter -InterfaceAlias $alias -ErrorAction SilentlyContinue
  if ($nic) { return [int]$nic.ifIndex }
  return 0
}

function Svc-Start([string]$tunnel, [int]$waitSec = 30) {
  $name = Svc-Name $tunnel
  if (-not (Svc-Ensure $tunnel)) { return $false }
  Say ('  starting ' + $name)
  cmd /c ('sc start "' + $name + '"') | Out-Null
  for ($i = 0; $i -lt $waitSec; $i++) {
    if (Iface-Up $tunnel) { Say ('  ' + $tunnel + ' is up, ifIndex ' + (Iface-Index $tunnel)); return $true }
    Start-Sleep -Seconds 1
  }
  Say ('  ' + $tunnel + ' did not come up in ' + $waitSec + ' seconds')
  return $false
}

function Pin-Route([string]$ip) {
  if ([string]::IsNullOrWhiteSpace($ip)) { return $false }
  $if1 = Iface-Index $Hop1
  if ($if1 -le 0) { return $false }
  $have = Get-NetRoute -DestinationPrefix ($ip + '/32') -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceIndex -eq $if1 }
  if ($have) { return $true }
  Say ('  re-adding the pin route ' + $ip + '/32 via ' + $Hop1 + ' (ifIndex ' + $if1 + ')')
  cmd /c ('route add ' + $ip + ' mask 255.255.255.255 0.0.0.0 if ' + $if1 + ' metric 1') | Out-Null
  Start-Sleep -Milliseconds 500
  $have = Get-NetRoute -DestinationPrefix ($ip + '/32') -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceIndex -eq $if1 }
  return [bool]$have
}

# ---- v5: the honest probe, read straight from the tunnel -------------------
# A TCP probe only proves "the internet answers". The tunnel itself knows when
# it last completed a handshake, and after patch 4 that number is readable on
#   \\.\pipe\ProtectedPrefix\Administrators\AwgChain\<tunnel>
# With PersistentKeepalive = 25 a live WireGuard session rekeys every ~120 s,
# so a handshake older than $HandshakeMaxAge means the hop is really gone.
$script:probeInfo = 'probe not run yet'
$script:epochStart = [datetime]::SpecifyKind([datetime]'1970-01-01T00:00:00', [System.DateTimeKind]::Utc)

function Epoch-Now() {
  return [int64]([datetime]::UtcNow - $script:epochStart).TotalSeconds
}

function Uapi-Keys([string]$name, [int]$timeoutMs = 3000) {
  foreach ($prefix in @('AwgChain', 'AmneziaWG')) {
    $pipe = $null
    try {
      $path = 'ProtectedPrefix\Administrators\' + $prefix + '\' + $name
      $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $path, [System.IO.Pipes.PipeDirection]::InOut)
      $pipe.Connect($timeoutMs)
      $writer = New-Object System.IO.StreamWriter($pipe)
      $writer.NewLine = "`n"
      $writer.AutoFlush = $true
      $writer.WriteLine('get=1')
      $writer.WriteLine('')
      $reader = New-Object System.IO.StreamReader($pipe)
      $keys = @{}
      while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq '') { break }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $k = $line.Substring(0, $i)
        $v = $line.Substring($i + 1)
        if ($keys.ContainsKey($k)) { $keys[$k] = @($keys[$k]) + $v } else { $keys[$k] = $v }
      }
      return $keys
    } catch {
    } finally {
      if ($pipe) { try { $pipe.Dispose() } catch { } }
    }
  }
  return $null
}

# -1 the pipe is silent, -2 the pipe answers but there was no handshake yet
function Handshake-Age([string]$name) {
  $keys = Uapi-Keys $name
  if ($null -eq $keys) { return [int64](-1) }
  $best = [int64]0
  if ($keys.ContainsKey('last_handshake_time_sec')) {
    foreach ($v in @($keys['last_handshake_time_sec'])) {
      $s = ([string]$v).Trim()
      $n = [int64]0
      try { $n = [int64]$s } catch { $n = 0 }
      if ($n -gt $best) { $best = $n }
    }
  }
  if ($best -le 0) { return [int64](-2) }
  $age = (Epoch-Now) - $best
  if ($age -lt 0) { $age = [int64]0 }
  return $age
}

function Fmt-Age([int64]$age) {
  if ($age -eq -1) { return 'no-pipe' }
  if ($age -eq -2) { return 'no-handshake' }
  return ([string]$age + 's')
}

# returns 'ok', 'stale' or 'nopipe'
function Probe-Handshake() {
  $a1 = Handshake-Age $Hop1
  $a2 = Handshake-Age $Hop2
  $script:probeInfo = 'handshake hop1=' + (Fmt-Age $a1) + ' hop2=' + (Fmt-Age $a2) + ' limit=' + $HandshakeMaxAge + 's'
  if ($a1 -eq -1 -or $a2 -eq -1) { return 'nopipe' }
  if ($a1 -eq -2 -or $a2 -eq -2) { return 'stale' }
  if ($a1 -le $HandshakeMaxAge -and $a2 -le $HandshakeMaxAge) { return 'ok' }
  return 'stale'
}

function Probe-Tcp([int]$timeoutMs = 4000) {
  $client = $null
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($ProbeHost, $ProbePort, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne($timeoutMs, $false)
    if ($ok -and $client.Connected) {
      $client.EndConnect($iar)
      $script:probeInfo = 'tcp ' + $ProbeHost + ':' + $ProbePort + ' ok'
      return $true
    }
    $script:probeInfo = 'tcp ' + $ProbeHost + ':' + $ProbePort + ' no answer'
    return $false
  } catch {
    $script:probeInfo = 'tcp ' + $ProbeHost + ':' + $ProbePort + ' error'
    return $false
  } finally {
    if ($client) { try { $client.Close() } catch { } }
  }
}

function Probe-Chain([int]$timeoutMs = 4000) {
  if ($Probe -eq 'tcp') { return (Probe-Tcp $timeoutMs) }
  $verdict = Probe-Handshake
  if ($verdict -eq 'ok') { return $true }
  if ($Probe -eq 'handshake') { return $false }
  # auto: the pipe is silent or the handshake is old, ask the network before
  # declaring the chain dead. This keeps the old behaviour as a safety net.
  $hsInfo = $script:probeInfo
  $tcp = Probe-Tcp $timeoutMs
  $script:probeInfo = $hsInfo + ' / ' + $script:probeInfo
  return $tcp
}

function Wait-Probe([int]$seconds = 30) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    if (Probe-Chain) { return $true }
    Start-Sleep -Seconds 2
  }
  return $false
}

function Guard-Proc() {
  return (Get-Process -Name 'awgchain-guard' -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Guard-Arm() {
  $script = Join-Path $PSScriptRoot 'guard-up.ps1'
  if (-not (Test-Path -LiteralPath $script)) {
    Say '  guard-up.ps1 not found next to the watchdog, the lock stays off'
    return $false
  }
  Say '  arming the kill switch (persistent)'
  & $script -Persist -Bin $Bin -Data $Data -Hop1 $Hop1 -Hop2 $Hop2 -LogDir $LogDir | ForEach-Object { Say ('    ' + $_) }
  Start-Sleep -Seconds 2
  $p = Guard-Proc
  if ($p) { Say ('  kill switch is armed, guard pid ' + $p.Id); return $true }
  Say '  the kill switch did not arm'
  return $false
}

function Recover([string]$ep2ip, [string]$reason) {
  Say ('RECOVERY=START reason=' + $reason)
  Say '  the kill switch stays armed for the whole recovery, nothing can leak'
  Svc-Stop $Hop2
  Svc-Stop $Hop1
  Start-Sleep -Seconds 2
  if (-not (Svc-Start $Hop1 30)) { Say 'RECOVERY=FAIL stage=hop1'; return $false }
  Start-Sleep -Seconds 2
  if (-not (Pin-Route $ep2ip)) { Say '  warning: the pin route is missing, hop 2 may go out directly' }
  if (-not (Svc-Start $Hop2 30)) { Say 'RECOVERY=FAIL stage=hop2'; return $false }
  Start-Sleep -Seconds 3
  if (Wait-Probe 45) { Say ('RECOVERY=OK ' + $script:probeInfo); return $true }
  Say 'RECOVERY=FAIL stage=probe'
  return $false
}

# ---------------------------------------------------------------- main

if (Test-Path -LiteralPath $stopFile) { Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue }

Say '=================================================='
Say 'WATCH=START'
Say ('  hop1     : ' + $Hop1)
Say ('  hop2     : ' + $Hop2)
Say ('  interval : ' + $Interval + ' seconds')
if ($Duration -gt 0) { Say ('  duration : ' + $Duration + ' seconds') } else { Say '  duration : until stopped' }
Say ('  probe    : ' + $Probe + ', handshake limit ' + $HandshakeMaxAge + 's, tcp fallback ' + $ProbeHost + ':' + $ProbePort)
Say ('  logs     : ' + $LogDir)
Say ('  stop with: awgchain-watch.bat stop')

$conf2 = Join-Path $Data ('Configurations\' + $Hop2 + '.conf')
$ep2 = Split-Endpoint (Get-ConfValue $conf2 'Endpoint')
$ep2ip = [string]$ep2.Host
Say ('  hop2 endpoint: ' + $ep2ip)

$lockWanted = $false
if ($WithLock -and -not $NoLock) { $lockWanted = $true }

if ($NoColdStart) {
  Say '  cold start is off, the watchdog only reacts to failures'
}
elseif (-not (Iface-Up $Hop1) -or -not (Iface-Up $Hop2)) {
  Say 'HEALTH=DOWN the chain is not up yet, bringing it up in order'
  if (Svc-Start $Hop1 30) {
    Pin-Route $ep2ip | Out-Null
    Svc-Start $Hop2 30 | Out-Null
  }
}

if (-not $NoColdStart) {
  if (Wait-Probe 45) {
    Say ('WARMUP=OK the chain answers, ' + $script:probeInfo)
  } else {
    Say 'WARMUP=SLOW the chain still does not answer'
  }
}

if ($lockWanted) {
  if (Guard-Proc) {
    Say ('  the kill switch is already armed, guard pid ' + (Guard-Proc).Id)
  } else {
    Guard-Arm | Out-Null
  }
}

$started = Get-Date
$fails = 0
$recoveries = 0
$lastState = ''

while ($true) {
  if (Test-Path -LiteralPath $stopFile) {
    Say 'WATCH=STOP reason=stopfile'
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
    break
  }
  if ($Duration -gt 0 -and ((Get-Date) - $started).TotalSeconds -ge $Duration) {
    Say 'WATCH=STOP reason=duration'
    break
  }

  $up1 = Iface-Up $Hop1
  $up2 = Iface-Up $Hop2
  $st1 = Svc-State (Svc-Name $Hop1)
  $st2 = Svc-State (Svc-Name $Hop2)
  $guard = Guard-Proc

  if ($lockWanted -and -not $guard) {
    Say 'LOCK=DOWN the guard process is gone, the filters died with it'
    Guard-Arm | Out-Null
    $guard = Guard-Proc
  }

  $reason = ''
  if (-not $up1) { $reason = 'hop1-down' }
  elseif (-not $up2) { $reason = 'hop2-down' }
  elseif ($ep2ip -ne '' -and -not (Pin-Route $ep2ip)) { $reason = 'pin-route-lost' }
  elseif (-not (Probe-Chain)) { $reason = 'no-traffic'; Say ('  probe: ' + $script:probeInfo) }

  $gtxt = 'off'
  if ($guard) { $gtxt = 'pid ' + $guard.Id }
  $ltxt = 'OK'
  if ($reason -ne '') { $ltxt = 'DEGRADED ' + $reason }

  if ($reason -eq '') {
    $fails = 0
    $state = 'HEALTH=OK hop1=' + $st1 + ' hop2=' + $st2 + ' guard=' + $gtxt
    if ($state -ne $lastState) { Say $state; $lastState = $state }
  } else {
    $fails++
    Say ('HEALTH=DEGRADED reason=' + $reason + ' strike ' + $fails + '/' + $FailsBeforeRecovery + ' hop1=' + $st1 + ' hop2=' + $st2)
    $lastState = ''
    if ($fails -ge $FailsBeforeRecovery) {
      if ($MaxRecoveries -gt 0 -and $recoveries -ge $MaxRecoveries) {
        Say ('WATCH=STOP reason=max-recoveries recoveries=' + $recoveries)
        break
      }
      $recoveries++
      $ok = Recover $ep2ip $reason
      $fails = 0
      if ($StopAfterRecovery) {
        if ($ok) { Say 'WATCH=STOP reason=recovered' } else { Say 'WATCH=STOP reason=recovery-failed' }
        break
      }
      Start-Sleep -Seconds 3
    }
  }

  try {
    Set-Content -LiteralPath $stateFile -Encoding UTF8 -Value @(
      ('updated    : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
      ('hop1       : ' + $st1 + ' iface=' + $up1),
      ('hop2       : ' + $st2 + ' iface=' + $up2),
      ('guard      : ' + $gtxt),
      ('recoveries : ' + $recoveries),
      ('last check : ' + $ltxt)
    )
  } catch { }

  if ($Once) { Say 'WATCH=STOP reason=once'; break }
  Start-Sleep -Seconds $Interval
}

Say ('WATCH=DONE recoveries=' + $recoveries)
if ($lockWanted -and (Guard-Proc)) {
  Say 'The kill switch is still armed. Release it with:  awgchain.bat ks off'
}
exit 0
