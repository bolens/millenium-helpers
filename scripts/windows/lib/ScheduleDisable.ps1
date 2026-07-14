# ScheduleDisable.ps1 - Schedule helpers for millennium-schedule.ps1

function Disable-Task {
    if (!(Test-Admin)) {
        Log-Error "Error: Administrator privileges are required to remove Scheduled Tasks."
        exit 1
    }

    Log-Info "Disabling and removing scheduled task '$taskName'..."
    Execute-Cmd -ScriptBlock {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -ne $task) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Log-Info "Scheduled task '$taskName' has been removed."
        } else {
            Log-Info "No scheduled task found to disable."
        }
    } -Description "Unregister-ScheduledTask -TaskName $taskName"
}
