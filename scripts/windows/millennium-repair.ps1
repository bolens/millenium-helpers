# Millennium Client Force Reinstall and Repair utility on Windows
param(
    [switch]$DryRun = $false,
    [Alias("y")]
    [switch]$Yes = $false,
    [Alias("h")]
    [switch]$Help = $false,
    [Alias("V")]
    [switch]$Version = $false
)
set-strictmode -version Latest

if ($Help) {
    Write-Host @"
Usage: millennium-repair.ps1 [-DryRun] [-Yes] [-Version] [-Help]

Force reinstall and repair the Millennium client on Windows.

Options:
  -DryRun      Simulate operations without modifying files
  -Yes, -y     Skip confirmation when closing Steam
  -Version, -V Show version information
  -Help, -h    Show this help message
"@
    exit 0
}

# Source shared helpers
$ScriptDir = $PSScriptRoot
$CommonPs1 = Join-Path -Path $ScriptDir -ChildPath "common.ps1"
if (Test-Path -Path $CommonPs1) {
    . $CommonPs1
} else {
    Write-Error "Shared helper library not found at $CommonPs1"
    exit 1
}

if ($Version) {
    Write-HelpersVersion -Name "millennium-repair"
    exit 0
}

if ($Yes) {
    $global:AssumeYes = $true
}

if ($DryRun) {
    $global:DryRun = $true
}

$SteamPath = Resolve-SteamPath
if (!$SteamPath) {
    Log-Error "Error: Steam installation path could not be resolved."
    exit 1
}

# Find configuration update channel
$Channel = "stable"
$configDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
$configFile = Join-Path -Path $configDir -ChildPath "config.json"
if (Test-Path -Path $configFile) {
    try {
        $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
        if ($config -and $config.update_channel) {
            $Channel = $config.update_channel
        }
    } catch {}
}

Log-Info "=== Initiating Millennium Force Repair ==="

# 1. Close Steam if running
$steamRunning = $null -ne (Get-Process -Name "steam" -ErrorAction SilentlyContinue)
if ($steamRunning) {
    Capture-SteamEnv
    if (-not (Confirm-CloseSteam)) {
        exit 1
    }
}

# 2. Invoke upgrade script with Force option
$upgradeScript = Join-Path -Path $ScriptDir -ChildPath "millennium-upgrade.ps1"
if (Test-Path -Path $upgradeScript) {
    $upgradeArgs = @("-Channel", $Channel, "-Force", "-Yes")
    if ($global:DryRun) { $upgradeArgs += "-DryRun" }
    Log-Info "Invoking client reinstalls: Powershell -File `"$upgradeScript`" $($upgradeArgs -join ' ')"
    Execute-Cmd -ScriptBlock {
        & $upgradeScript @upgradeArgs
    } -Description "powershell -File $upgradeScript -Channel $Channel -Force -Yes"
} else {
    Log-Error "Error: Upgrade script not found at $upgradeScript"
}

# 3. Refresh scheduled tasks
$scheduleScript = Join-Path -Path $ScriptDir -ChildPath "millennium-schedule.ps1"
if (Test-Path -Path $scheduleScript) {
    # If task is configured, let's enable it again
    $taskName = "MillenniumUpdate"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $task -and (Test-Admin)) {
        Log-Info "Re-registering auto-update scheduled task..."
        Execute-Cmd -ScriptBlock {
            & $scheduleScript enable $Channel
        } -Description "powershell -File $scheduleScript enable $Channel"
    }
}

if ($steamRunning) {
    Relaunch-Steam
}

Log-Info "Repair completed successfully."
exit 0
