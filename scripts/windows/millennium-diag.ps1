# Diagnostics and status reporter for Millennium helper scripts on Windows
param(
    [string]$Command = $null,
    [switch]$Force = $false,
    [switch]$Json = $false,
    [switch]$DryRun = $false,
    [switch]$Share = $false
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

if ($Share) {
    Write-Host "Generating and uploading diagnostic report..."
    
    # Run the diagnostics command itself (without the -Share switch) to capture the output
    $cleanArgs = @()
    if ($Json) { $cleanArgs += "-Json" }
    if ($DryRun) { $cleanArgs += "-DryRun" }
    if ($Force) { $cleanArgs += "-Force" }
    if ($Command) { $cleanArgs += $Command }
    
    $reportOutput = & $PSCommandPath @cleanArgs 2>&1 | Out-String
    
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

# Support command alias doctor
if ($args.Count -gt 0 -and ($args[0] -eq "doctor" -or $args[0] -eq "-f" -or $args[0] -eq "--fix")) {
    $Command = "doctor"
}

if ($DryRun) {
    $global:DryRun = $true
}

$SteamPath = Resolve-SteamPath
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

if ($diagReport["steam_running"]) {
    Print-DiagItem -Status "ok" -Label "Steam Client" -Value "Running (PID: $($diagReport['steam_pid']))"
} else {
    Print-DiagItem -Status "error" -Label "Steam Client" -Value "Not Running"
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
    Print-DiagItem -Status "error" -Label "Auto-Update Task Scheduler" -Value "Disabled / Not Scheduled"
}

if ($CleanOfObsolete) {
    Print-DiagItem -Status "ok" -Label "Legacy Wrapper Files" -Value "None detected (Clean)"
} else {
    Print-DiagItem -Status "error" -Label "Legacy Wrapper Files" -Value "Detected $($obsoleteFilesFound.Count) deprecated files needing cleanup"
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

    # Issue 1: Missing or corrupted binaries
    if (!$BinariesOk) {
        Write-Host "`n[DOCTOR] Repairing Millennium binaries..."
        $upgradeScript = Join-Path -Path $ScriptDir -ChildPath "millennium-upgrade.ps1"
        if (Test-Path -Path $upgradeScript) {
            $upgradeArgs = "-Channel $Channel -Force"
            if ($global:DryRun) { $upgradeArgs += " -DryRun" }
            Log-Info "Invoking upgrade script: Powershell -File `"$upgradeScript`" $upgradeArgs"
            Execute-Cmd -ScriptBlock {
                & $upgradeScript -Channel $Channel -Force
            } -Description "powershell -File $upgradeScript -Channel $Channel -Force"
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
        Write-Host -ForegroundColor Green "`nDoctor repairs applied successfully! Re-run diagnostics to verify."
    }
}
exit 0
