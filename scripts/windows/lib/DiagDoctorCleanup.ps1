# DiagDoctorCleanup.ps1 — Doctor cleanup phase:
#   1. Remove obsolete/deprecated files
#   2. Warn on mixed install
#   3. Package upgrade hints (and optional -Yes self-heal for scoop/winget)

function Invoke-DoctorCleanup {
    $needsClean = !$script:CleanOfObsolete -or $global:Force

    if ($needsClean) {
        Write-Host "`n[DOCTOR] Cleaning up obsolete / deprecated legacy files..."
        if ($script:ObsoleteFilesFound.Count -gt 0) {
            foreach ($f in $script:ObsoleteFilesFound) {
                Log-Info "Removing deprecated file: $f"
                Execute-Cmd -ScriptBlock {
                    Remove-Item -Path $f -Force
                } -Description "Remove-Item -Path `"$f`" -Force"
            }
        } else {
            Log-Info 'No obsolete files found.'
        }
    }

    # Warn on mixed install — cannot auto-repair
    if ($script:InstallMethod -eq 'mixed') {
        Write-Host ''
        Write-Host -ForegroundColor Yellow '[WARN] Mixed install detected (scoop/winget/manual).'
        Write-Host '  Automatic script sync is disabled until the conflict is resolved.'
        Write-Host '  Remove the conflicting installation method, then re-run: millennium doctor'
    }

    # Package upgrade for managed installs with outdated scripts
    if (!$script:ScriptsUpToDate -and $script:InstallMethod -in @('scoop', 'winget')) {
        Write-Host "`n[DOCTOR] Helper scripts are outdated — upgrade via package manager:"
        Print-PackageUpgradeHint

        if ($global:AssumeYes) {
            if ($global:DryRun) {
                switch ($script:InstallMethod) {
                    'scoop'  { Log-Warn '[DRY RUN] Would run: scoop update millennium-helpers' }
                    'winget' { Log-Warn '[DRY RUN] Would run: winget upgrade bolens.millenniumhelpers' }
                }
            } else {
                Write-Host "[DOCTOR] -Yes specified — running package upgrade ($($script:InstallMethod))..."
                switch ($script:InstallMethod) {
                    'scoop' {
                        Execute-Cmd -ScriptBlock {
                            & scoop update millennium-helpers
                        } -Description 'scoop update millennium-helpers'
                    }
                    'winget' {
                        Execute-Cmd -ScriptBlock {
                            & winget upgrade --id bolens.millenniumhelpers --accept-package-agreements --accept-source-agreements
                        } -Description 'winget upgrade bolens.millenniumhelpers'
                    }
                }
            }
        } else {
            Write-Host -ForegroundColor Yellow 'Tip: re-run with -Yes to run the package upgrade automatically.'
        }
    }
}
