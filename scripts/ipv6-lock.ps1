param(
  [switch]$On,
  [switch]$Off,
  [switch]$Status,
  [switch]$Reapply
)

$ErrorActionPreference = "Stop"
$stateDir  = "C:\ProgramData\AwgChain"
$stateFile = Join-Path $stateDir "ipv6-lock-state.json"
$taskName  = "AwgChainIPv6Lock"
$selfPath  = $MyInvocation.MyCommand.Path

function Get-Bindings {
  Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "Loopback*" }
}

function Write-State($rows) {
  if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
  $rows | ConvertTo-Json -Depth 4 | Set-Content -Path $stateFile -Encoding ASCII
}

# used by the scheduled task at boot: just re-apply the lock, no output
if ($Reapply) {
  foreach ($b in Get-Bindings) {
    if ($b.Enabled) { Disable-NetAdapterBinding -Name $b.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue }
  }
  exit 0
}

if ($Status) {
  $b = Get-Bindings
  $on = @($b | Where-Object { $_.Enabled })
  foreach ($x in $b) {
    $flag = "off"
    if ($x.Enabled) { $flag = "ON" }
    Write-Host ("  {0,-28} ipv6 {1}" -f $x.Name, $flag)
  }
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Write-Host "boot task     : present"
  } else {
    Write-Host "boot task     : absent"
  }
  Write-Host ""
  if ($on.Count -eq 0) { Write-Host "RESULT=LOCKED" } else { Write-Host "RESULT=UNLOCKED" }
  exit 0
}

if ($On) {
  $rows = @()
  $changed = 0
  foreach ($b in Get-Bindings) {
    $rows += [pscustomobject]@{ Name = $b.Name; Enabled = [bool]$b.Enabled }
    if ($b.Enabled) {
      try {
        Disable-NetAdapterBinding -Name $b.Name -ComponentID ms_tcpip6 -ErrorAction Stop
        Write-Host ("[OK] IPv6 off on " + $b.Name)
        $changed++
      } catch {
        Write-Host ("[WARN] could not disable IPv6 on " + $b.Name)
      }
    }
  }
  Write-State $rows
  Write-Host ("previous state saved to " + $stateFile)
  Write-Host ("adapters changed: " + $changed)

  # boot task, so the lock survives reboots and new adapters
  $quote = [char]34
  $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + $quote + $selfPath + $quote + ' -Reapply'
  try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $act = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
    $trg = New-ScheduledTaskTrigger -AtStartup
    $pri = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $act -Trigger $trg -Principal $pri -Settings $set | Out-Null
    Write-Host "[OK] boot task installed, the lock survives reboots"
  } catch {
    Write-Host "[WARN] boot task not installed, the lock works until reboot"
  }

  Write-Host ""
  Write-Host "RESULT=OK"
  exit 0
}

if ($Off) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  $known = @{}
  if (Test-Path $stateFile) {
    try {
      $saved = Get-Content $stateFile -Raw | ConvertFrom-Json
      foreach ($row in $saved) { $known[$row.Name] = [bool]$row.Enabled }
    } catch { }
  }
  foreach ($b in Get-Bindings) {
    $want = $true
    if ($known.ContainsKey($b.Name)) { $want = $known[$b.Name] }
    if ($want -and -not $b.Enabled) {
      try {
        Enable-NetAdapterBinding -Name $b.Name -ComponentID ms_tcpip6 -ErrorAction Stop
        Write-Host ("[OK] IPv6 back on " + $b.Name)
      } catch {
        Write-Host ("[WARN] could not enable IPv6 on " + $b.Name)
      }
    }
  }
  Write-Host ""
  Write-Host "RESULT=OK"
  exit 0
}

Write-Host "usage: ipv6-lock.ps1 -On | -Off | -Status"
Write-Host "RESULT=FAIL"
exit 1
