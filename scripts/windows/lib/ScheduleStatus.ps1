# ScheduleStatus.ps1 - Schedule helpers for millennium-schedule.ps1

function Show-Status {
    Log-Info "=== Millennium Scheduled Task Status ==="
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Write-Host "  Task Name   : $($task.TaskName)"
        Write-Host "  Path        : $($task.TaskPath)"
        Write-Host "  State       : $($task.State)"
        Write-Host "  Action      : $(($task.Actions | Select-Object -First 1).Execute) $(($task.Actions | Select-Object -First 1).Arguments)"
        $channelDisp = $Channel
        $actionArgs = "$(($task.Actions | Select-Object -First 1).Arguments)"
        if ($actionArgs -match '-Channel\s+(\S+)') {
            $channelDisp = $Matches[1]
        }
        $logFile = $updaterLog
        Write-Host ""
        Write-Host "=== Scheduler summary ==="
        Write-Host "  Channel     : $channelDisp"
        if (Test-Path -Path $logFile) {
            Write-Host "  Last log    : $logFile"
            Write-Host "  View logs   : millennium diag logs"
        } else {
            Write-Host "  Last log    : (none yet - runs after the first scheduled update)"
        }
        Write-Host "  Disable     : millennium schedule disable"
    } else {
        Write-Host "  Scheduled task is not registered."
        Write-Host ""
        Write-Host -ForegroundColor Yellow "Scheduler disabled. Enable with: millennium schedule enable [stable|beta|main]"
    }
}
