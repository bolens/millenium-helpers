# ScheduleEnable.ps1 - Schedule helpers for millennium-schedule.ps1

function Enable-Task {
    param([Parameter(Mandatory = $true)][string]$ChannelArg)
    try {
        $channel_arg = Require-UpdateChannel -Channel $ChannelArg
    } catch {
        Log-Error $_.Exception.Message
        exit 1
    }
    $upgradeScript = Join-Path -Path $ScriptDir -ChildPath "millennium-upgrade.ps1"
    $themeScript = Join-Path -Path $ScriptDir -ChildPath "millennium-theme.ps1"

    if (!(Test-Path -Path $upgradeScript)) {
        Log-Error "Error: Millennium upgrade script not found at $upgradeScript"
        exit 1
    }

    if (!(Test-Admin)) {
        Log-Error "Error: Administrator privileges are required to configure Scheduled Tasks."
        exit 1
    }

    Log-Info "Configuring Windows Task Scheduler task '$taskName' ($channel_arg channel)..."

    # Generate random start delay to prevent DDoS on GitHub
    $delayMin = Get-Random -Minimum 0 -Maximum 60

    # Escape single quotes in paths for embedding inside single-quoted PowerShell literals.
    $escConfigDir = $configDir.Replace("'", "''")
    $escUpgrade = $upgradeScript.Replace("'", "''")
    $escTheme = $themeScript.Replace("'", "''")
    $escLog = $updaterLog.Replace("'", "''")
    # Channel is allow-listed; embed as a single-quoted literal so injection cannot break out.
    $psInner = @(
        "New-Item -ItemType Directory -Force -Path '$escConfigDir' | Out-Null"
        "& '$escUpgrade' -Channel '$channel_arg' -Yes -Quiet *>> '$escLog'"
        "if (Test-Path -LiteralPath '$escTheme') { & '$escTheme' update -Quiet *>> '$escLog' }"
    ) -join "; "
    $taskArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$psInner`""

    Log-Info "Task command: powershell.exe $taskArg"

    Execute-Cmd -ScriptBlock {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArg
        $trigger = New-ScheduledTaskTrigger -Daily -At "2:00AM"
        $trigger.RandomDelay = [System.TimeSpan]::FromMinutes($delayMin)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    } -Description "Register-ScheduledTask -TaskName $taskName"

    Log-Info "Millennium auto-update scheduled task has been enabled!"
    Log-Info "It will run daily with a randomized delay of up to 1 hour."
    Log-Info "Logs append to: $updaterLog"
}
