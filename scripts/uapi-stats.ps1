<#
  uapi-stats.ps1  v3

  Reads the UAPI named pipe that each tunnel listens on and prints the only
  numbers that really say whether a hop is alive: the age of the last
  handshake and the transfer counters.

  After patch 4 the pipe is
    \\.\pipe\ProtectedPrefix\Administrators\AwgChain\<tunnel>
  The old AmneziaWG name is still tried, so the script also works against a
  binary built before patch 4.

  Examples
    powershell -NoProfile -ExecutionPolicy Bypass -File uapi-stats.ps1 -All
    powershell -NoProfile -ExecutionPolicy Bypass -File uapi-stats.ps1 -Tunnel hop2-amnezia
    powershell -NoProfile -ExecutionPolicy Bypass -File uapi-stats.ps1 -All -Raw

  Needs an elevated shell: the pipe is protected for Administrators.
#>
param(
  [string]$Tunnel = '',
  [switch]$All,
  [string]$Hop1 = 'hop1-warp',
  [string]$Hop2 = 'hop2-amnezia',
  [int]$TimeoutMs = 5000,
  [switch]$Raw
)

$ErrorActionPreference = 'Continue'
$epochStart = [datetime]::SpecifyKind([datetime]'1970-01-01T00:00:00', [System.DateTimeKind]::Utc)

function Epoch-Now() {
  return [int64]([datetime]::UtcNow - $epochStart).TotalSeconds
}

function Uapi-Get([string]$name, [int]$timeoutMs) {
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
      $lines = New-Object System.Collections.Generic.List[string]
      while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq '') { break }
        $lines.Add($line) | Out-Null
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $k = $line.Substring(0, $i)
        $v = $line.Substring($i + 1)
        if ($keys.ContainsKey($k)) { $keys[$k] = @($keys[$k]) + $v } else { $keys[$k] = $v }
      }
      return [pscustomobject]@{ Prefix = $prefix; Keys = $keys; Lines = $lines }
    } catch {
    } finally {
      if ($pipe) { try { $pipe.Dispose() } catch { } }
    }
  }
  return $null
}

function Sum-Key($keys, [string]$name) {
  $total = [int64]0
  if (-not $keys.ContainsKey($name)) { return $total }
  foreach ($v in @($keys[$name])) {
    $s = ([string]$v).Trim()
    try { $total = $total + [int64]$s } catch { }
  }
  return $total
}

function Max-Key($keys, [string]$name) {
  $best = [int64]0
  if (-not $keys.ContainsKey($name)) { return $best }
  foreach ($v in @($keys[$name])) {
    $s = ([string]$v).Trim()
    $n = [int64]0
    try { $n = [int64]$s } catch { $n = 0 }
    if ($n -gt $best) { $best = $n }
  }
  return $best
}

function First-Key($keys, [string]$name) {
  if (-not $keys.ContainsKey($name)) { return '' }
  return ([string](@($keys[$name])[0])).Trim()
}

function Human([int64]$bytes) {
  if ($bytes -ge 1073741824) { return ([math]::Round($bytes / 1073741824, 2).ToString() + ' GB') }
  if ($bytes -ge 1048576) { return ([math]::Round($bytes / 1048576, 2).ToString() + ' MB') }
  if ($bytes -ge 1024) { return ([math]::Round($bytes / 1024, 1).ToString() + ' KB') }
  return ($bytes.ToString() + ' B')
}

function Report([string]$name) {
  Write-Host ('--- ' + $name + ' ---')
  $res = Uapi-Get $name $TimeoutMs
  if ($null -eq $res) {
    Write-Host '  the tunnel does not answer on its UAPI pipe'
    Write-Host '  is the service running? is this shell elevated?'
    Write-Host ('STATS ' + $name + ' pipe=none handshake=n/a')
    return $false
  }

  $keys = $res.Keys
  $hs = Max-Key $keys 'last_handshake_time_sec'
  $rx = Sum-Key $keys 'rx_bytes'
  $tx = Sum-Key $keys 'tx_bytes'
  $ep = First-Key $keys 'endpoint'
  $port = First-Key $keys 'listen_port'
  $errno = First-Key $keys 'errno'

  $ageTxt = 'never'
  $age = [int64](-1)
  if ($hs -gt 0) {
    $age = (Epoch-Now) - $hs
    if ($age -lt 0) { $age = 0 }
    $ageTxt = [string]$age + 's ago'
  }

  $verdict = 'STALE'
  if ($hs -gt 0 -and $age -le 180) { $verdict = 'ALIVE' }

  Write-Host ('  pipe      : ' + $res.Prefix + '\' + $name)
  Write-Host ('  handshake : ' + $ageTxt + '  -> ' + $verdict)
  Write-Host ('  endpoint  : ' + $ep)
  Write-Host ('  listening : udp ' + $port)
  Write-Host ('  received  : ' + (Human $rx))
  Write-Host ('  sent      : ' + (Human $tx))
  if ($errno -ne '' -and $errno -ne '0') { Write-Host ('  errno     : ' + $errno) }

  if ($Raw) {
    Write-Host '  --- raw ---'
    foreach ($l in $res.Lines) {
      if ($l -like 'private_key=*' -or $l -like 'preshared_key=*') { continue }
      Write-Host ('  ' + $l)
    }
  }

  Write-Host ('STATS ' + $name + ' pipe=' + $res.Prefix + ' handshake=' + $ageTxt + ' verdict=' + $verdict + ' rx=' + $rx + ' tx=' + $tx)
  Write-Host ''
  return ($verdict -eq 'ALIVE')
}

$targets = @()
if ($All -or [string]::IsNullOrWhiteSpace($Tunnel)) { $targets = @($Hop1, $Hop2) } else { $targets = @($Tunnel) }

Write-Host ('UAPI stats  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Host ''

$bad = 0
foreach ($t in $targets) {
  $ok = Report $t
  if (-not $ok) { $bad++ }
}

if ($bad -gt 0) {
  Write-Host ('RESULT=STALE ' + $bad + ' of ' + $targets.Count + ' hops have no fresh handshake')
  exit 1
}
Write-Host ('RESULT=OK all ' + $targets.Count + ' hops handshook recently')
exit 0
