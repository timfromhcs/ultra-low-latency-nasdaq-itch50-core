param(
  [switch]$Disable
)
# =============================================================================
# File: scripts/register_heartbeat.ps1
# Description: Register (or remove) the hourly ChipLab heartbeat task.
#   powershell -ExecutionPolicy Bypass -File scripts/register_heartbeat.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/register_heartbeat.ps1 -Disable
# =============================================================================
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$TaskName = "ChipLabHeartbeat"
$Script = Join-Path $PSScriptRoot "heartbeat.ps1"

if ($Disable) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Removed scheduled task $TaskName"
  exit 0
}

$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" -InvokeAgent -Tick" `
  -WorkingDirectory $Root
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddHours(1) `
  -RepetitionInterval (New-TimeSpan -Hours 1) `
  -RepetitionDuration (New-TimeSpan -Days 3650)
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -MultipleInstances IgnoreNew
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
  -Settings $Settings -Principal $Principal -Force | Out-Null
Write-Host "Registered $TaskName (hourly). Log: $Root\reports\heartbeat.log"
Write-Host "Disable with: powershell -File scripts/register_heartbeat.ps1 -Disable"
