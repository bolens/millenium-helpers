# DiagDoctor.ps1 - Doctor orchestrator
#   Flow: healthy check -> force flags -> Steam close -> cleanup -> runtime repair -> relaunch

function Invoke-DoctorRepairs {
    Write-Host "`n=== Running Millennium Doctor (Automatic Repairs) ==="

    $needsRepair = (
        !$script:BinariesOk      -or
        !$script:PermissionsOk   -or
        !$script:SkinsDirOk      -or
        !$script:TaskOk          -or
        !$script:CleanOfObsolete -or
        !$script:ScriptsUpToDate -or
        !$script:CompletionsOk   -or
        $script:InstallMethod -eq 'mixed'
    )

    if (!$global:Force -and !$needsRepair) {
        Write-Host -ForegroundColor Green 'No issues detected. Your Millennium installation is healthy!'
        return
    }

    if ($global:Force) {
        Write-Host -ForegroundColor Yellow 'Force option specified. Forcing all doctor repairs...'
        $script:BinariesOk      = $false
        $script:SkinsDirOk      = $false
        $script:TaskOk          = $false
        $script:CleanOfObsolete = $false
        $script:ScriptsUpToDate = $false
        $script:CompletionsOk   = $false
    }

    # Close Steam if binary repair is needed
    $relaunchSteam = $false
    if ($script:SteamRunning -and !$script:BinariesOk) {
        if (Is-GameRunning) {
            Log-Error 'A Steam game is currently running. Doctor repairs cannot proceed.'
            Write-Host 'Close the running game, then re-run. Use -Yes to skip the Steam close prompt.'
            return
        }
        Write-Host -ForegroundColor Yellow 'Steam is currently running and must be closed to apply binary repairs.'
        if (!$global:DryRun) {
            Capture-SteamEnv
            if (!(Confirm-CloseSteam)) { return }
        } else {
            Log-Warn '[DRY RUN] Would capture Steam environment and close it.'
        }
        $script:SteamRunning = $false
        $relaunchSteam       = $true
    }

    # Phase 1: Cleanup (obsolete files + mixed warning + package upgrade hints)
    Invoke-DoctorCleanup

    # Phase 2 & 3: Runtime repair (binaries, skins, task, manual script sync)
    Invoke-DoctorRepair

    # Footer
    if ($global:DryRun) {
        Write-Host -ForegroundColor Green "`nDoctor dry-run simulation finished successfully!"
    } else {
        Write-Host -ForegroundColor Green "`nDoctor repairs applied successfully."
        Write-Host "Channel: $($script:Channel). Re-run 'millennium-diag' to verify."
    }

    # Relaunch Steam if it was closed for repairs
    if ($relaunchSteam) {
        Write-Host -ForegroundColor Green "`nRelaunching Steam..."
        if ($global:DryRun) {
            Log-Warn '[DRY RUN] Would relaunch Steam.'
        } else {
            Relaunch-Steam
            Write-Host -ForegroundColor Green 'Steam relaunched.'
        }
    }

    # Cleanup temp release extract
    Invoke-DiagReleaseCleanup
}
