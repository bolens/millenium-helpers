# UpgradeRollback.ps1 - Rollback helpers for millennium-upgrade.ps1

function Invoke-UpgradeRollback {
    param(
        [Parameter(Mandatory = $true)][string]$RollbackTarget,
        [Parameter(Mandatory = $true)][string]$BackupDirArg,
        [Parameter(Mandatory = $true)][string]$MillenniumDirArg,
        [Parameter(Mandatory = $true)][string]$WsockDllArg
    )

    if ($RollbackTarget -eq "list") {
        Log-Info "Available backups for rollback:"
        if (Test-Path -Path $BackupDirArg) {
            $backups = Get-ChildItem -Path $BackupDirArg -Directory | Sort-Object CreationTime -Descending
            if ($backups.Count -eq 0) {
                Write-Host "  No backups found."
            } else {
                foreach ($b in $backups) {
                    Write-Host "  - $($b.Name) (Created: $($b.CreationTime))"
                }
            }
        } else {
            Write-Host "  No backups directory exists."
        }
        Write-Host ""
        Write-Host "Apply one with: millennium upgrade -Rollback <id>"
        return "list"
    }

    $targetBackup = Join-Path -Path $BackupDirArg -ChildPath $RollbackTarget
    if (!(Test-Path -Path $targetBackup)) {
        Log-Error "Error: Backup '$RollbackTarget' not found."
        return "error"
    }

    if (Is-GameRunning) {
        Log-Error "Error: A Steam game is currently running. Rollback aborted."
        Write-Host "Close the running game, then re-run. Use -Yes to skip the Steam close prompt."
        return "error"
    }

    $steamRunning = $null -ne (Get-Process -Name "steam" -ErrorAction SilentlyContinue)
    if ($steamRunning) {
        Capture-SteamEnv
        if (-not (Confirm-CloseSteam)) {
            return "aborted"
        }
    }

    Log-Info "Rolling back Millennium installation to $RollbackTarget..."
    $md = $MillenniumDirArg
    $wd = $WsockDllArg
    $tb = $targetBackup
    $rollbackBlock = {
        if (Test-Path -Path $md) {
            Remove-Item -Path $md -Recurse -Force
        }
        if (Test-Path -Path $wd) {
            Remove-Item -Path $wd -Force
        }
        Copy-Item -Path (Join-Path -Path $tb -ChildPath "millennium") -Destination $md -Recurse -Force
        Copy-Item -Path (Join-Path -Path $tb -ChildPath "wsock32.dll") -Destination $wd -Force
        Remove-Item -Path $tb -Recurse -Force
    }.GetNewClosure()
    Execute-Cmd -ScriptBlock $rollbackBlock -Description "Rollback using backup $tb"

    Log-Info "Rollback completed successfully."
    if ($steamRunning) {
        Relaunch-Steam
        Write-Host -ForegroundColor Green "Steam relaunched."
    }
    return "ok"
}
