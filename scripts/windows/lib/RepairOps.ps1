# RepairOps.ps1 - Repair operations for millennium-repair.ps1

function Invoke-MillenniumRepair {
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
                $cand = [string]$config.update_channel
                if (Test-ValidUpdateChannel -Channel $cand) {
                    $Channel = $cand
                } else {
                    Log-Warn "Ignoring invalid update_channel '$cand' in config (expected stable|beta|main)."
                }
            }
        } catch {}
    }
    try {
        $Channel = Require-UpdateChannel -Channel $Channel
    } catch {
        Log-Error $_.Exception.Message
        exit 1
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
        if ($global:Quiet -or $env:MILLENNIUM_QUIET) { $upgradeArgs += "-Quiet" }
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
            if ($global:Quiet -or $env:MILLENNIUM_QUIET) { $themeArgs += "-Quiet" }
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
}
