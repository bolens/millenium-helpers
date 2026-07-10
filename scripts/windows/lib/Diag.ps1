# Diag.ps1 - Loader: dot-sources all diag modules and exposes the top-level API.
#
# Callers MUST set before sourcing or before calling Invoke-DiagnosticsChecks:
#   $script:DiagLibDir    - directory containing the lib/*.ps1 files
#   $script:SteamPath     - resolved Steam installation path
#   $script:MillenniumDir - SteamPath\millennium
#   $script:WsockDll      - SteamPath\wsock32.dll
#   $script:SkinsDir      - SteamPath\steamui\skins
#   $script:Channel       - update channel (stable / beta)
#   $script:VersionStr    - installed Millennium version string (or 'Not Installed')
#   $script:ScriptDir     - directory containing the top-level *.ps1 scripts

# Initialize shared path state with safe defaults.
# $script:DiagLibDir must be set by the caller BEFORE sourcing this file.
# The other path variables are set by the caller AFTER sourcing; initialize
# them to empty defaults here so StrictMode doesn't throw in module-level code.
$script:SteamPath     = ''
$script:MillenniumDir = ''
$script:WsockDll      = ''
$script:SkinsDir      = ''
$script:Channel       = 'stable'
$script:VersionStr    = 'Not Installed'
$script:ScriptDir     = ''

# Dot-source all modules (order matters: dependencies first)
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagUi.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagSteam.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagEnv.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagCompletions.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagInstall.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagRelease.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagUpdates.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagNextSteps.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagDoctorCleanup.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagDoctorRepair.ps1')
. (Join-Path -Path $script:DiagLibDir -ChildPath 'DiagDoctor.ps1')

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

function Invoke-DiagnosticsChecks {
    # Populate all $script: state; no console output.
    Get-DiagSteamStatus
    Get-DiagBinariesStatus
    Get-DiagPermissionsStatus
    Get-DiagSkinsDirStatus
    Get-DiagTaskStatus
    Get-DiagObsoleteStatus
    Get-DiagCompletionsStatus
    Get-DiagInstallMethod
    Test-HelperScriptsUpToDate
}

function Write-DiagReport {
    # Human-readable output only - never called in JSON mode.
    Write-Host '=== Millennium Diagnostics Report ==='
    Write-Host ''

    # Steam & binaries
    if ($script:SteamRunning) {
        Print-DiagItem -Status 'ok'   -Label 'Steam Client'             -Value "Running (PID: $($script:SteamPid))"
    } else {
        Print-DiagItem -Status 'warn' -Label 'Steam Client'             -Value 'Not Running'
    }
    if ($script:BinariesOk) {
        Print-DiagItem -Status 'ok'   -Label 'Millennium Binary Version' -Value $script:BinariesStatus
    } else {
        Print-DiagItem -Status 'error' -Label 'Millennium Binary Version' -Value $script:BinariesStatus
    }

    # Install method section
    Show-DiagInstallMethod

    # Helper scripts update status
    Write-Host "`nHelper Scripts Update Status:"
    if ($script:ScriptsUpToDate) {
        $tagLabel = if ($script:LatestReleaseTag) { $script:LatestReleaseTag } else { 'unknown' }
        Print-DiagItem -Status 'ok' -Label 'Helper scripts' -Value "Up to date ($tagLabel)"
    } elseif ($script:InstallMethod -eq 'mixed') {
        Print-DiagItem -Status 'error' -Label 'Helper scripts' -Value 'Mixed install - resolve conflict before updating'
    } elseif ($script:OutOfDateScripts.Count -gt 0) {
        $tagLabel = if ($script:LatestReleaseTag) { $script:LatestReleaseTag } else { 'unknown' }
        foreach ($s in $script:OutOfDateScripts) {
            Print-DiagItem -Status 'error' -Label "  - $s" -Value "Out of date (latest: $tagLabel)"
        }
    } else {
        Print-DiagItem -Status 'warn' -Label 'Helper scripts' -Value 'Could not determine update status (offline?)'
    }

    # Permissions & directories
    Write-Host "`nPermissions & Directories:"
    if ($script:PermissionsOk) {
        Print-DiagItem -Status 'ok'    -Label 'Steam Folder Permissions' -Value 'Writable'
    } else {
        Print-DiagItem -Status 'error' -Label 'Steam Folder Permissions' `
            -Value "Not Writable ($($script:UnwritableDirs -join ', '))"
    }
    if ($script:SkinsDirOk) {
        Print-DiagItem -Status 'ok'    -Label 'Skins/Themes Directory'   -Value "Present ($($script:SkinsDir))"
    } else {
        Print-DiagItem -Status 'error' -Label 'Skins/Themes Directory'   -Value 'Missing (will be created by doctor)'
    }

    # Auto-updates
    Write-Host "`nAuto-Updates:"
    if ($script:TaskOk) {
        Print-DiagItem -Status 'ok'   -Label 'Auto-Update Task Scheduler' -Value "Enabled (State: $($script:TaskState))"
    } else {
        Print-DiagItem -Status 'warn' -Label 'Auto-Update Task Scheduler' -Value 'Disabled / Not Scheduled'
    }
    if ($script:CleanOfObsolete) {
        Print-DiagItem -Status 'ok'   -Label 'Legacy Wrapper Files'       -Value 'None detected (Clean)'
    } else {
        Print-DiagItem -Status 'warn' -Label 'Legacy Wrapper Files' `
            -Value "Detected $($script:ObsoleteFilesFound.Count) deprecated file(s) needing cleanup"
    }

    Write-Host "`nShell Completions:"
    if ($script:CompletionsOk) {
        $compLabel = if ($script:CompletionFilePath) { $script:CompletionFilePath } else { 'Present' }
        Print-DiagItem -Status 'ok' -Label 'PowerShell completions' -Value $compLabel
    } else {
        $bits = @()
        if ($script:CompletionFileMissing) { $bits += 'completer file missing' }
        if ($script:CompletionHookMissing) { $bits += 'profile hook missing' }
        Print-DiagItem -Status 'error' -Label 'PowerShell completions' -Value ($bits -join '; ')
    }
}

function Invoke-DiagnosticsReport {
    # Convenience: run checks then print human-readable report.
    Invoke-DiagnosticsChecks
    Write-DiagReport
}

function Get-DiagJsonObject {
    return [ordered]@{
        steam_running      = $script:SteamRunning
        binaries_ok        = $script:BinariesOk
        permissions_ok     = $script:PermissionsOk
        skins_dir_ok       = $script:SkinsDirOk
        task_scheduled     = $script:TaskOk
        clean_of_obsolete  = $script:CleanOfObsolete
        completions_ok     = $script:CompletionsOk
        scripts_up_to_date = $script:ScriptsUpToDate
        install_method     = $script:InstallMethod
        mixed_install_ok   = $script:MixedInstallOk
        helpers_checkout   = $script:HelpersCheckout
        latest_release_tag = $script:LatestReleaseTag
        update_channel     = $script:Channel
        version            = $script:VersionStr
    }
}
