# Millennium Client Force Reinstall and Repair utility on Windows
param(
    [switch]$DryRun = $false,
    [Alias("y")]
    [switch]$Yes = $false,
    [Alias("q")]
    [switch]$Quiet = $false,
    [Alias("s")]
    [switch]$SkipTheme = $false,
    [Alias("h")]
    [switch]$Help = $false,
    [Alias("V")]
    [switch]$Version = $false
)
set-strictmode -version Latest

# Source shared helpers
$ScriptDir = $PSScriptRoot
$CommonPs1 = Join-Path -Path $ScriptDir -ChildPath "common.ps1"
if (Test-Path -Path $CommonPs1) {
    . $CommonPs1
} else {
    Write-Error "Shared helper library not found at $CommonPs1"
    exit 1
}

if ($args.Count -gt 0) {
    $gnuFlags = @{
        DryRun    = [bool]$DryRun
        Yes       = [bool]$Yes
        Quiet     = [bool]$Quiet
        SkipTheme = [bool]$SkipTheme
        Help      = [bool]$Help
        Version   = [bool]$Version
    }
    [void](Apply-GnuStyleArgs -InputArgs ([string[]]$args) -Target $gnuFlags)
    if ($gnuFlags.DryRun) { $DryRun = $true }
    if ($gnuFlags.Yes) { $Yes = $true }
    if ($gnuFlags.Quiet) { $Quiet = $true; $global:Quiet = $true; $env:MILLENNIUM_QUIET = "1" }
    if ($gnuFlags.SkipTheme) { $SkipTheme = $true }
    if ($gnuFlags.Help) { $Help = $true }
    if ($gnuFlags.Version) { $Version = $true }
}

if ($Help) {
    Write-Host @"
Usage: millennium-repair.ps1 [-DryRun] [-Yes] [-Quiet] [-SkipTheme] [-Version] [-Help]

Force reinstall the Millennium client on Windows (via millennium-upgrade -Force),
optionally refresh installed themes, and re-register the auto-update task if present.

Options:
  -DryRun         Simulate operations without modifying files
  -Yes, -y        Skip confirmation when closing Steam
  -Quiet, -q      Suppress informational output
  -SkipTheme, -s  Skip theme refresh after reinstall
  -Version, -V    Show version information
  -Help, -h       Show this help message

GNU-style flags (--skip-theme, --yes, --quiet, --dry-run) are also accepted.
"@
    exit 0
}

if ($Version) {
    Write-HelpersVersion -Name "millennium-repair"
    exit 0
}

if ($Yes) {
    $global:AssumeYes = $true
}

if ($Quiet) {
    $global:Quiet = $true
    $env:MILLENNIUM_QUIET = "1"
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
    if ($Quiet) { $upgradeArgs += "-Quiet" }
    Log-Info "Invoking client reinstall: Powershell -File `"$upgradeScript`" $($upgradeArgs -join ' ')"
    Execute-Cmd -ScriptBlock {
        & $upgradeScript @upgradeArgs
    } -Description "powershell -File $upgradeScript -Channel $Channel -Force -Yes"
} else {
    Log-Error "Error: Upgrade script not found at $upgradeScript"
}

# 3. Refresh installed themes (Unix repair refreshes the active theme unless --skip-theme)
if (-not $SkipTheme) {
    $themeScript = Join-Path -Path $ScriptDir -ChildPath "millennium-theme.ps1"
    if (Test-Path -Path $themeScript) {
        Log-Info "Refreshing installed themes..."
        $themeArgs = @("update")
        if ($Quiet) { $themeArgs += "-Quiet" }
        if ($global:DryRun) { $themeArgs += "-DryRun" }
        Execute-Cmd -ScriptBlock {
            & $themeScript @themeArgs
        } -Description "powershell -File $themeScript update"
    }
}

# 4. Refresh scheduled tasks
$scheduleScript = Join-Path -Path $ScriptDir -ChildPath "millennium-schedule.ps1"
if (Test-Path -Path $scheduleScript) {
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
