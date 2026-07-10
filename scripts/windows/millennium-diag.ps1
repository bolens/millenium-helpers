# Diagnostics and status reporter for Millennium helper scripts on Windows
param(
    [string]$Command = $null,
    [switch]$Force = $false,
    [switch]$Json = $false,
    [switch]$DryRun = $false,
    [switch]$Share = $false,
    [Alias("l")]
    [switch]$Follow = $false,
    [Alias("y")]
    [switch]$Yes = $false,
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

if ($Help -or $Command -eq "help" -or $Command -eq "--help" -or $Command -eq "-h") {
    Write-Output @"
Usage: millennium-diag [COMMAND] [OPTIONS]

Commands:
  (None)        Run read-only diagnostics report (default)
  doctor        Detect and automatically repair partial or broken installations
  logs          Display recent Millennium and Steam WebHelper startup logs

Options:
  -Force        Force all doctor repairs even if system is healthy
  -Json         Output diagnostics report in structured JSON format
  -DryRun       Simulate doctor repairs without modifying anything
  -Share        Upload diagnostic report to a pastebin and return a short link
  -Follow, -l   Follow (tail -f) real-time log output
  -Yes, -y      Skip confirmation when doctor closes Steam
  -Version, -V  Show version information
  -Help, -h     Show this help message
"@
    exit 0
}
if ($Version -or $Command -eq "version" -or $Command -eq "--version" -or $Command -eq "-V") {
    Write-HelpersVersion -Name "millennium-diag"
    exit 0
}

if ($Yes) {
    $global:AssumeYes = $true
}

if ($Share) {
    Write-Host "Generating and uploading diagnostic report..."
    
    # Run the diagnostics command itself (without the -Share switch) to capture the output
    $cleanArgs = @()
    if ($Json) { $cleanArgs += "-Json" }
    if ($DryRun) { $cleanArgs += "-DryRun" }
    if ($Force) { $cleanArgs += "-Force" }
    if ($Yes) { $cleanArgs += "-Yes" }
    if ($Command) { $cleanArgs += $Command }
    
    $reportOutput = & $PSCommandPath @cleanArgs *>&1 | Out-String
    
    # Redact user directory and user name
    $userName = $env:USERNAME
    $userProfile = $env:USERPROFILE
    
    if ($userProfile) {
        $escapedProfile = [regex]::Escape($userProfile)
        $reportOutput = $reportOutput -replace $escapedProfile, "~"
    }
    if ($userName) {
        $reportOutput = $reportOutput -replace $userName, "user"
    }
    
    # Redact GitHub tokens and PATs
    $reportOutput = $reportOutput -replace "ghp_[A-Za-z0-9_]+", "[REDACTED]"
    $reportOutput = $reportOutput -replace "github_pat_[A-Za-z0-9_]+", "[REDACTED]"
    
    # Retrieve configuration token from config.json if present
    $configDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
    $configFile = Join-Path -Path $configDir -ChildPath "config.json"
    if (Test-Path -Path $configFile) {
        try {
            $configObj = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            if ($configObj -and $configObj.github_token -and $configObj.github_token.Length -ge 4) {
                $reportOutput = $reportOutput -replace [regex]::Escape($configObj.github_token), "[REDACTED]"
            }
        } catch {}
    }
    
    if ($env:GITHUB_TOKEN -and $env:GITHUB_TOKEN.Length -ge 4) {
        $reportOutput = $reportOutput -replace [regex]::Escape($env:GITHUB_TOKEN), "[REDACTED]"
    }
    
    # Upload to paste.rs
    try {
        $response = Invoke-RestMethod -Uri "https://paste.rs" -Method Post -Body $reportOutput -ContentType "text/plain; charset=utf-8"
        if ($response -and $response -like "*http*") {
            Write-Host -ForegroundColor Green "Diagnostic report successfully shared!"
            Write-Host -NoNewline "URL: "
            Write-Host -ForegroundColor Blue $response.Trim()
        } else {
            Write-Error "Error: Failed to upload diagnostic report to paste.rs. (Invalid response: $response)"
            exit 1
        }
    } catch {
        Write-Error "Error: Failed to upload diagnostic report to paste.rs. ($($_.Exception.Message))"
        exit 1
    }
    exit 0
}

# Support command aliases
if ($args.Count -gt 0) {
    if ($args[0] -eq "doctor" -or $args[0] -eq "-f" -or $args[0] -eq "--fix") {
        $Command = "doctor"
    } elseif ($args[0] -eq "logs") {
        $Command = "logs"
    }
}

if ($DryRun) {
    $global:DryRun = $true
}

$SteamPath = Resolve-SteamPath

# --- Logs Viewer Execution ---
if ($Command -eq "logs") {
    $helpersStateDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
    $updaterLog = Join-Path -Path $helpersStateDir -ChildPath "updater.log"
    if (Test-Path -Path $updaterLog) {
        Write-Host -ForegroundColor Blue "=== Millennium Background Auto-Updater Logs ==="
        Get-Content -Path $updaterLog -Tail 50 -ErrorAction SilentlyContinue
        Write-Host ""
    }

    Write-Host -ForegroundColor Blue "=== Millennium & Steam WebHelper Logs ==="

    if (!$SteamPath) {
        Log-Error "Error: Steam installation path could not be resolved."
        exit 1
    }

    $steamLogsDir = Join-Path -Path $SteamPath -ChildPath "logs"
    $logNames = @(
        "webhelper.txt",
        "console_log.txt",
        "console.txt",
        "content_log.txt",
        "stderr.txt",
        "stdout.txt"
    )
    $logFiles = @()
    foreach ($logName in $logNames) {
        $candidate = Join-Path -Path $steamLogsDir -ChildPath $logName
        if (Test-Path -Path $candidate -PathType Leaf) {
            $logFiles += Get-Item -Path $candidate
        }
    }

    if ($logFiles.Count -eq 0) {
        Log-Error "Error: No Steam logs found under $steamLogsDir."
        exit 1
    }

    $latestLog = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host -ForegroundColor Yellow "Reading log file: $($latestLog.FullName)`n"

    $filterRegex = "Millennium|BOOTSTRAP|update-check|plugin_loader|steamwebhelper|wsock32"

    if ($Follow) {
        Write-Host "Tailing log file (Ctrl+C to exit)..."
        Get-Content -Path $latestLog.FullName -Tail 100 -Wait | Where-Object { $_ -match $filterRegex }
    } else {
        $matches = Get-Content -Path $latestLog.FullName -Tail 200 -ErrorAction SilentlyContinue |
            Where-Object { $_ -match $filterRegex }
        if ($matches) {
            $matches | ForEach-Object { Write-Host $_ }
        } else {
            Write-Host "No recent Millennium-related log entries found."
        }
    }
    exit 0
}

$SteamRunning = $null -ne (Get-Process -Name "steam" -ErrorAction SilentlyContinue)
$BinariesOk = $true
$SkinsDirOk = $true
$TaskOk = $true
$PermissionsOk = $true
$CleanOfObsolete = $true

$unwritableDirs = @()
$obsoleteFilesFound = @()

# Verify installer path
if (!$SteamPath) {
    Log-Error "Error: Steam installation path could not be resolved."
    exit 1
}

$MillenniumDir = Join-Path -Path $SteamPath -ChildPath "millennium"
$WsockDll = Join-Path -Path $SteamPath -ChildPath "wsock32.dll"
$SkinsDir = Join-Path -Path $SteamPath -ChildPath "steamui\skins"

# Parse configuration channel
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

# --- Diagnostic Check Logic ---

$diagReport = [ordered]@{}

# 1. Steam Client Status
if ($SteamRunning) {
    $p = Get-Process -Name "steam" -ErrorAction SilentlyContinue | Select-Object -First 1
    $diagReport["steam_running"] = $true
    $diagReport["steam_pid"] = $p.Id
} else {
    $diagReport["steam_running"] = $false
}

# 2. Binary version & health checks
$installedVerFile = Join-Path -Path $MillenniumDir -ChildPath "version.txt"
$versionStr = "Not Installed"
if (Test-Path -Path $installedVerFile) {
    $versionStr = (Get-Content -Path $installedVerFile -Raw).Trim()
}

$coreFiles = @(
    $WsockDll,
    (Join-Path -Path $MillenniumDir -ChildPath "lib\millennium.dll"),
    (Join-Path -Path $MillenniumDir -ChildPath "lib\millennium.hhx64.dll"),
    (Join-Path -Path $MillenniumDir -ChildPath "bin\millennium.crashhandler64.exe"),
    (Join-Path -Path $MillenniumDir -ChildPath "bin\millennium.luavm64.exe")
)

$missingCore = $false
foreach ($f in $coreFiles) {
    if (!(Test-Path -Path $f)) {
        $missingCore = $true
        $BinariesOk = $false
    }
}

if ($missingCore) {
    $diagReport["binaries_ok"] = $false
    $diagReport["binaries_status"] = "Corrupted (missing core files)"
} elseif ($versionStr -eq "Not Installed") {
    $diagReport["binaries_ok"] = $false
    $diagReport["binaries_status"] = "Not Installed"
} else {
    $diagReport["binaries_ok"] = $true
    $diagReport["binaries_status"] = "v$versionStr ($Channel channel) - Verified Healthy"
}

# 3. Permissions Checks
# Test folder write access
function Test-FolderWrite {
    param([string]$Path)
    if (!(Test-Path -Path $Path)) { return $true }
    try {
        $testFile = Join-Path -Path $Path -ChildPath "permissions_test.txt"
        New-Item -ItemType File -Path $testFile -Force | Out-Null
        Remove-Item -Path $testFile -Force | Out-Null
        return $true
    } catch {
        return $false
    }
}

if (!(Test-FolderWrite -Path $SteamPath)) {
    $PermissionsOk = $false
    $unwritableDirs += $SteamPath
}
if (!(Test-FolderWrite -Path $SkinsDir)) {
    $PermissionsOk = $false
    $unwritableDirs += $SkinsDir
}

$diagReport["permissions_ok"] = $PermissionsOk
if (!(Test-Path -Path $SkinsDir)) {
    $SkinsDirOk = $false
}
$diagReport["skins_dir_ok"] = $SkinsDirOk

# 4. Scheduled Tasks Status (Daily Auto-Updates)
$taskName = "MillenniumUpdate"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $task) {
    $diagReport["task_scheduled"] = $true
    $diagReport["task_state"] = $task.State.ToString()
} else {
    $diagReport["task_scheduled"] = $false
    $TaskOk = $false
}

# 5. Check Obsolete / Deprecated Legacy Files
# Replicate cleaning up stable/beta wrapper scripts or files on Windows
$obsoleteList = @(
    (Join-Path -Path $SteamPath -ChildPath "millennium-upgrade-stable.ps1"),
    (Join-Path -Path $SteamPath -ChildPath "millennium-upgrade-beta.ps1")
)

foreach ($f in $obsoleteList) {
    if (Test-Path -Path $f) {
        $CleanOfObsolete = $false
        $obsoleteFilesFound += $f
    }
}
$diagReport["clean_of_obsolete"] = $CleanOfObsolete

# --- Print Report Output ---

if ($Json) {
    $jsonObj = @{
        "steam_running" = $diagReport["steam_running"];
        "binaries_ok" = $diagReport["binaries_ok"];
        "permissions_ok" = $diagReport["permissions_ok"];
        "skins_dir_ok" = $diagReport["skins_dir_ok"];
        "task_scheduled" = $diagReport["task_scheduled"];
        "clean_of_obsolete" = $diagReport["clean_of_obsolete"];
        "update_channel" = $Channel;
        "version" = $versionStr;
    }
    $jsonObj | ConvertTo-Json
    exit 0
}

# Standard human-readable console output
Write-Host "=== Millennium Diagnostics Report ===`n"

function Print-DiagItem {
    param(
        [string]$Status,
        [string]$Label,
        [string]$Value
    )
    if ($Status -eq "ok") {
        Write-Host -NoNewline "  [ " -ForegroundColor White
        Write-Host -NoNewline "OK" -ForegroundColor Green
        Write-Host -NoNewline " ] " -ForegroundColor White
    } elseif ($Status -eq "warn") {
        Write-Host -NoNewline "  [" -ForegroundColor White
        Write-Host -NoNewline "WARN" -ForegroundColor Yellow
        Write-Host -NoNewline "] " -ForegroundColor White
    } else {
        Write-Host -NoNewline "  [" -ForegroundColor White
        Write-Host -NoNewline "FAIL" -ForegroundColor Red
        Write-Host -NoNewline "] " -ForegroundColor White
    }
    # Print label padded
    $paddedLabel = $Label.PadRight(45)
    Write-Host -NoNewline $paddedLabel
    Write-Host " : $Value"
}

function Print-DiagNextSteps {
    $issues = 0
    $suggestions = [System.Collections.Generic.List[string]]::new()

    if (-not $diagReport["binaries_ok"]) {
        $issues++
        $suggestions.Add("millennium upgrade -Force         # repair/reinstall Millennium binaries")
    }
    if (-not $PermissionsOk) {
        $issues++
        $suggestions.Add("millennium repair                 # fix Steam folder permissions")
    }
    if (-not $SkinsDirOk) {
        $issues++
        $suggestions.Add("millennium doctor                 # create missing skins directory")
    }
    if (-not $diagReport["task_scheduled"]) {
        $issues++
        $suggestions.Add("millennium schedule enable        # enable daily auto-updates")
    }
    if (-not $CleanOfObsolete) {
        $issues++
        $suggestions.Add("millennium doctor                 # remove legacy wrapper files")
    }

    Write-Host ""
    if ($issues -eq 0) {
        Write-Host -ForegroundColor Green "No issues detected. Your Millennium installation looks healthy."
        Write-Host "Tip: run ${YELLOW}millennium schedule status${NC} to review auto-updates, or ${YELLOW}millennium theme list${NC} for skins."
        return
    }

    Write-Host -ForegroundColor Yellow "$issues issue(s) detected. Suggested next steps:"
    $seen = @{}
    foreach ($s in $suggestions) {
        if ($seen.ContainsKey($s)) { continue }
        $seen[$s] = $true
        Write-Host "  • $s"
    }
    Write-Host ""
    Write-Host "Or run ${GREEN}millennium doctor${NC} to attempt automatic repairs."
}

if ($diagReport["steam_running"]) {
    Print-DiagItem -Status "ok" -Label "Steam Client" -Value "Running (PID: $($diagReport['steam_pid']))"
} else {
    Print-DiagItem -Status "warn" -Label "Steam Client" -Value "Not Running"
}

if ($diagReport["binaries_ok"]) {
    Print-DiagItem -Status "ok" -Label "Millennium Binary Version" -Value $diagReport["binaries_status"]
} else {
    Print-DiagItem -Status "error" -Label "Millennium Binary Version" -Value $diagReport["binaries_status"]
}

Write-Host "`nPermissions & Directories:"
if ($PermissionsOk) {
    Print-DiagItem -Status "ok" -Label "Steam Folder Permissions" -Value "Writable"
} else {
    Print-DiagItem -Status "error" -Label "Steam Folder Permissions" -Value "Not Writable"
}

if ($SkinsDirOk) {
    Print-DiagItem -Status "ok" -Label "Skins/Themes Directory" -Value "Present ($SkinsDir)"
} else {
    Print-DiagItem -Status "error" -Label "Skins/Themes Directory" -Value "Missing (parent is writable, will be created)"
}

if ($diagReport["task_scheduled"]) {
    Print-DiagItem -Status "ok" -Label "Auto-Update Task Scheduler" -Value "Enabled (State: $($diagReport['task_state']))"
} else {
    Print-DiagItem -Status "warn" -Label "Auto-Update Task Scheduler" -Value "Disabled / Not Scheduled"
}

if ($CleanOfObsolete) {
    Print-DiagItem -Status "ok" -Label "Legacy Wrapper Files" -Value "None detected (Clean)"
} else {
    Print-DiagItem -Status "warn" -Label "Legacy Wrapper Files" -Value "Detected $($obsoleteFilesFound.Count) deprecated files needing cleanup"
}

# Actionable next steps for the default (read-only) report
if ($Command -ne "doctor") {
    Print-DiagNextSteps
}

# --- Doctor / Auto-Repair Execution ---
if ($Command -eq "doctor") {
    Write-Host "`n=== Running Millennium Doctor (Automatic Repairs) ==="
    
    # Check if repairs are needed
    if (!$Force) {
        if ($diagReport["binaries_ok"] -and $PermissionsOk -and $SkinsDirOk -and $diagReport["task_scheduled"] -and $CleanOfObsolete) {
            Write-Host -ForegroundColor Green "No issues detected. Your Millennium installation is healthy!"
            exit 0
        }
    } else {
        Write-Host -ForegroundColor Yellow "Force option specified. Forcing all doctor repairs..."
        $BinariesOk = $false
        $SkinsDirOk = $false
        $TaskOk = $false
        $CleanOfObsolete = $false
    }

    $relaunchSteamAfterDoctor = $false
    if ($SteamRunning -and (-not $BinariesOk)) {
        if (Is-GameRunning) {
            Log-Error "Error: A Steam game is currently running. Doctor repairs cannot proceed while a game is active."
            exit 1
        }

        Write-Host -ForegroundColor Yellow "Steam is currently running and must be closed to apply repairs to binaries."

        if (-not $global:DryRun) {
            Capture-SteamEnv
            if (-not (Confirm-CloseSteam)) {
                exit 1
            }
        } else {
            Log-Warn "[DRY RUN] Would capture Steam's environment and close it to apply repairs."
        }

        $SteamRunning = $false
        $relaunchSteamAfterDoctor = $true
    }

    # Issue 1: Missing or corrupted binaries
    if (!$BinariesOk) {
        Write-Host "`n[DOCTOR] Repairing Millennium binaries..."
        $upgradeScript = Join-Path -Path $ScriptDir -ChildPath "millennium-upgrade.ps1"
        if (Test-Path -Path $upgradeScript) {
            $upgradeArgs = @("-Channel", $Channel, "-Force", "-Yes")
            if ($global:DryRun) { $upgradeArgs += "-DryRun" }
            Log-Info "Invoking upgrade script: Powershell -File `"$upgradeScript`" $($upgradeArgs -join ' ')"
            Execute-Cmd -ScriptBlock {
                & $upgradeScript @upgradeArgs
            } -Description "powershell -File $upgradeScript -Channel $Channel -Force -Yes"
        } else {
            Log-Error "Upgrade script not found at $upgradeScript"
        }
    }

    # Issue 2: Missing Skins directory
    if (!$SkinsDirOk) {
        Write-Host "`n[DOCTOR] Creating missing skins directory..."
        Execute-Cmd -ScriptBlock {
            New-Item -ItemType Directory -Force -Path $SkinsDir | Out-Null
        } -Description "New-Item -ItemType Directory -Path $SkinsDir"
    }

    # Issue 3: Missing Scheduled Task
    if (!$TaskOk) {
        Write-Host "`n[DOCTOR] Creating daily auto-update scheduled task..."
        $scheduleScript = Join-Path -Path $ScriptDir -ChildPath "millennium-schedule.ps1"
        if (Test-Path -Path $scheduleScript) {
            Execute-Cmd -ScriptBlock {
                & $scheduleScript enable $Channel
            } -Description "powershell -File $scheduleScript enable $Channel"
        } else {
            Log-Error "Schedule script not found at $scheduleScript"
        }
    }

    # Issue 4: Cleanup obsolete legacy files
    if (!$CleanOfObsolete) {
        Write-Host "`n[DOCTOR] Cleaning up obsolete / deprecated legacy files..."
        foreach ($f in $obsoleteFilesFound) {
            Log-Info "Removing deprecated file: $f"
            Execute-Cmd -ScriptBlock {
                Remove-Item -Path $f -Force
            } -Description "Remove-Item -Path $f -Force"
        }
    }

    if ($global:DryRun) {
        Write-Host -ForegroundColor Green "`nDoctor dry-run simulation finished successfully!"
    } else {
        Write-Host -ForegroundColor Green "`nDoctor repairs applied successfully."
        Write-Host "Channel: $Channel. Re-run ${YELLOW}millennium-diag${NC} to verify, or ${YELLOW}millennium-diag doctor${NC} again if issues remain."
    }

    if ($relaunchSteamAfterDoctor) {
        Write-Host -ForegroundColor Green "`nRelaunching Steam..."
        if ($global:DryRun) {
            Log-Warn "[DRY RUN] Would relaunch Steam."
        } else {
            Relaunch-Steam
            Write-Host -ForegroundColor Green "Steam relaunched."
        }
    }
}
exit 0
