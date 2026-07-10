# DiagDoctorRepair.ps1 — Doctor runtime repair phase:
#   1. Millennium binaries (via millennium-upgrade.ps1)
#   2. Missing skins directory
#   3. Missing scheduled task
#   4. Manual helper script sync from release zip (skipped for scoop/winget)
#   5. PowerShell completions (file + profile hook)

function Invoke-DoctorRepair {
    # 1. Repair / reinstall Millennium binaries
    if (!$script:BinariesOk -or $global:Force) {
        Write-Host "`n[DOCTOR] Repairing Millennium binaries..."
        $upgradeScript = Join-Path -Path $script:ScriptDir -ChildPath 'millennium-upgrade.ps1'
        if (Test-Path -Path $upgradeScript) {
            $upgradeArgs = @('-Channel', $script:Channel, '-Force', '-Yes')
            if ($global:DryRun) { $upgradeArgs += '-DryRun' }
            Log-Info "Invoking: millennium-upgrade.ps1 $($upgradeArgs -join ' ')"
            Execute-Cmd -ScriptBlock {
                & $upgradeScript @upgradeArgs
            } -Description "millennium-upgrade.ps1 -Channel $($script:Channel) -Force -Yes"
        } else {
            Log-Error "Upgrade script not found at: $upgradeScript"
        }
    }

    # 2. Create missing skins directory
    if (!$script:SkinsDirOk -or $global:Force) {
        Write-Host "`n[DOCTOR] Creating missing skins directory..."
        Execute-Cmd -ScriptBlock {
            New-Item -ItemType Directory -Force -Path $script:SkinsDir | Out-Null
        } -Description "New-Item -ItemType Directory -Path `"$($script:SkinsDir)`""
    }

    # 3. Enable scheduled task
    if (!$script:TaskOk -or $global:Force) {
        Write-Host "`n[DOCTOR] Enabling daily auto-update scheduled task..."
        $scheduleScript = Join-Path -Path $script:ScriptDir -ChildPath 'millennium-schedule.ps1'
        if (Test-Path -Path $scheduleScript) {
            Execute-Cmd -ScriptBlock {
                & $scheduleScript enable $script:Channel
            } -Description "millennium-schedule.ps1 enable $($script:Channel)"
        } else {
            Log-Error "Schedule script not found at: $scheduleScript"
        }
    }

    # 4. Sync helper scripts from release zip (manual install only)
    if (!$script:ScriptsUpToDate) {
        if ($script:InstallMethod -in @('scoop', 'winget')) {
            # Already handled in Invoke-DoctorCleanup
        } elseif ($script:InstallMethod -eq 'manual') {
            Write-Host "`n[DOCTOR] Syncing helper scripts from latest release zip..."
            _Invoke-ManualScriptSync
        } elseif ($script:InstallMethod -eq 'mixed') {
            Write-Host "`n[DOCTOR] Skipping script sync — resolve mixed install first."
        }
    }

    # 5. Repair PowerShell completions (file + profile hook)
    if (!$script:CompletionsOk -or $global:Force) {
        Write-Host "`n[DOCTOR] Repairing PowerShell completions..."
        if ($script:InstallMethod -in @('scoop', 'winget')) {
            Write-Host '  Packaged install — reinstall/upgrade the package to restore completions, e.g.:'
            Print-PackageUpgradeHint
            # Still try to restore a missing profile hook pointing at the packaged completer
            if ($script:CompletionHookMissing -and $script:CompletionFilePath -and (Test-Path -Path $script:CompletionFilePath)) {
                _Invoke-RegisterCompletionHook -CompletionPath $script:CompletionFilePath
            }
        } else {
            _Invoke-RepairCompletions
        }
    }
}

function _Invoke-RegisterCompletionHook {
    param([Parameter(Mandatory = $true)][string]$CompletionPath)

    $hook = ". `"$CompletionPath`""
    foreach ($profilePath in (Get-DiagProfilePaths)) {
        if ([string]::IsNullOrWhiteSpace($profilePath)) { continue }
        $profileDir = Split-Path -Parent -Path $profilePath
        if (!(Test-Path -Path $profileDir)) {
            Execute-Cmd -ScriptBlock {
                New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
            } -Description "New-Item -ItemType Directory -Path `"$profileDir`""
        }
        $existing = ''
        if (Test-Path -Path $profilePath) {
            $existing = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
        }
        if ($existing -like '*millennium-helpers.completion.ps1*' -or
            $existing -like '*completions*powershell*millennium-helpers.ps1*') {
            continue
        }
        Log-Info "Registering completion hook in $profilePath"
        Execute-Cmd -ScriptBlock {
            Add-Content -Path $profilePath -Value "`n# Millennium Helpers completions`n$hook`n"
        } -Description "Add-Content completion hook → $profilePath"
    }
}

function _Invoke-RepairCompletions {
    $dest = $script:CompletionFilePath
    if (-not $dest) {
        if ($script:ScriptDir) {
            $dest = Join-Path -Path $script:ScriptDir -ChildPath 'millennium-helpers.completion.ps1'
        } elseif ($env:USERPROFILE) {
            $dest = Join-Path -Path $env:USERPROFILE -ChildPath '.millennium-helpers\bin\millennium-helpers.completion.ps1'
        }
    }
    if (-not $dest) {
        Log-Warn 'Cannot determine completion install path; skipping.'
        return
    }

    if ($script:CompletionFileMissing -or !(Test-Path -Path $dest)) {
        $src = $null
        if (!$script:DiagReleaseExtract) {
            $null = Get-ReleaseZipExtract
        }
        if ($script:DiagReleaseExtract) {
            $src = Get-ReleaseSourcePath -RelativePath 'completions\powershell\millennium-helpers.ps1'
        }
        if (-not $src -and $script:HelpersCheckout) {
            $checkoutSrc = Join-Path -Path $script:HelpersCheckout -ChildPath 'completions\powershell\millennium-helpers.ps1'
            if (Test-Path -Path $checkoutSrc) { $src = $checkoutSrc }
        }
        if ($src -and (Test-Path -Path $src)) {
            $destDir = Split-Path -Parent -Path $dest
            if (!(Test-Path -Path $destDir)) {
                Execute-Cmd -ScriptBlock {
                    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                } -Description "New-Item -ItemType Directory -Path `"$destDir`""
            }
            Log-Info "Restoring completion file: $dest"
            Execute-Cmd -ScriptBlock {
                Copy-Item -Path $src -Destination $dest -Force
            } -Description "Copy-Item completions → $dest"
            $script:CompletionFilePath = $dest
        } else {
            Log-Warn 'Could not locate completion source in release zip or checkout; skipping file restore.'
        }
    }

    if ($script:CompletionFilePath -and (Test-Path -Path $script:CompletionFilePath)) {
        _Invoke-RegisterCompletionHook -CompletionPath $script:CompletionFilePath
    }
}

function _Invoke-ManualScriptSync {
    if (-not $env:USERPROFILE) {
        Log-Warn 'Cannot sync manual scripts: USERPROFILE environment variable is not set.'
        return
    }
    $binDir = Join-Path -Path $env:USERPROFILE -ChildPath '.millennium-helpers\bin'

    # Fetch release zip if not already extracted
    if (!$script:DiagReleaseExtract) {
        if (!(Get-ReleaseZipExtract)) {
            Log-Error "Could not download release zip for script sync. Try again later."
            return
        }
    }

    # Sync key top-level scripts
    foreach ($relPath in $script:KeyScripts) {
        $scriptName  = Split-Path -Leaf $relPath
        $releasePath = Get-ReleaseSourcePath -RelativePath $relPath
        if (!$releasePath) {
            Log-Warn "Script not in release zip: $relPath"
            continue
        }
        $destPath = Join-Path -Path $binDir -ChildPath $scriptName
        Log-Info "Syncing: $scriptName"
        Execute-Cmd -ScriptBlock {
            Copy-Item -Path $releasePath -Destination $destPath -Force
        } -Description "Copy-Item $scriptName from release zip"
    }

    # Sync lib/*.ps1 modules
    $libRelDir  = 'scripts\windows\lib'
    $libExtract = Get-ReleaseSourcePath -RelativePath $libRelDir
    if ($libExtract) {
        $libDest = Join-Path -Path $binDir -ChildPath 'lib'
        if (!(Test-Path -Path $libDest)) {
            New-Item -ItemType Directory -Force -Path $libDest | Out-Null
        }
        Get-ChildItem -Path $libExtract -Filter '*.ps1' -ErrorAction SilentlyContinue |
            ForEach-Object {
                $srcFile  = $_.FullName
                $destFile = Join-Path -Path $libDest -ChildPath $_.Name
                Log-Info "Syncing lib: $($_.Name)"
                Execute-Cmd -ScriptBlock {
                    Copy-Item -Path $srcFile -Destination $destFile -Force
                } -Description "Copy-Item lib\$($_.Name) from release zip"
            }
    }
}
