param(
  [switch]$InvokeAgent,
  [switch]$Tick,
  [switch]$DryRun
)
# =============================================================================
# File: scripts/heartbeat.ps1
# Description: Hourly heartbeat for the ChipLab autonomy loop.
#   - always appends a timestamped "hallo, es ist <time>" line
#   - with -InvokeAgent, resumes the newest OpenCode session in this project
#     and asks it to run the autonomy tick and then continue the active plan
# =============================================================================
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$Log = Join-Path $Root "reports\heartbeat.log"
New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
$Now = Get-Date
$Line = "[{0}] hallo, es ist {1}" -f $Now.ToString("o"), $Now.ToString("HH:mm")
Add-Content -Path $Log -Value $Line -Encoding utf8

if ($Tick) {
  Push-Location $Root
  try {
    $out = & node scripts/autonomy.mjs 2>&1
    Add-Content -Path $Log -Value ($out -join "`n") -Encoding utf8
  } finally { Pop-Location }
}

if ($InvokeAgent) {
  Push-Location $Root
  try {
    $Prompt = "Hallo, es ist $($Now.ToString('HH:mm')). Autonomy tick: run node scripts/autonomy.mjs, read the result, fix any failing gate, append a short entry to EXECUTION_LOG.md, then continue with the next unchecked item in STABLE_RELEASE_PLAN.md (or LONG_TERM_PLAN.md if the release plan is done). Do not stop early: keep working autonomously until that item is complete and verified, then pick the next one. Only stop if you are truly blocked or the user interrupts."
    $SessionFile = Join-Path $Root "autonomy\session.txt"
    $RunArgs = @("run", "--auto")
    if (Test-Path $SessionFile) {
      $SessionId = (Get-Content $SessionFile -Raw).Trim()
      if ($SessionId) { $RunArgs += @("--session", $SessionId) }
    } else {
      $RunArgs += "--continue"
    }
    $RunArgs += $Prompt
    if ($DryRun) {
      Add-Content -Path $Log -Value ("[heartbeat] dry-run: opencode " + ($RunArgs -join " ")) -Encoding utf8
    } else {
      & opencode @RunArgs 2>&1 | Out-File -FilePath $Log -Append -Encoding utf8
    }
  } catch {
    Add-Content -Path $Log -Value "[heartbeat] opencode failed: $_" -Encoding utf8
  } finally { Pop-Location }
}
