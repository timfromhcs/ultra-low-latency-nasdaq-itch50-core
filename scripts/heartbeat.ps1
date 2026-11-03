param(
  [switch]$InvokeAgent,
  [switch]$Tick
)
# =============================================================================
# File: scripts/heartbeat.ps1
# Description: Hourly heartbeat for the ChipLab autonomy loop.
#   - always appends a timestamped "hallo, es ist <time>" line
#   - with -InvokeAgent, resumes the newest OpenCode session in this project
#     and asks for one bounded autonomy tick
# =============================================================================
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$Log = Join-Path $Root "reports\heartbeat.log"
New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
$Now = Get-Date
$Line = "[{0}] hallo, es ist {1}" -f $Now.ToString("o"), $Now.ToString("HH:mm")
Add-Content -Path $Log -Value $Line

if ($Tick) {
  Push-Location $Root
  try {
    $out = & node scripts/autonomy.mjs 2>&1
    Add-Content -Path $Log -Value ($out -join "`n")
  } finally { Pop-Location }
}

if ($InvokeAgent) {
  Push-Location $Root
  try {
    $Prompt = "Hallo, es ist $($Now.ToString('HH:mm')). Autonomy tick: run `node scripts/autonomy.mjs`, read the result, fix one failing gate if needed, append to EXECUTION_LOG.md, then stop. Do not start long new work."
    & opencode run --continue --auto --prompt $Prompt *>> $Log
  } catch {
    Add-Content -Path $Log -Value "[heartbeat] opencode failed: $_"
  } finally { Pop-Location }
}
