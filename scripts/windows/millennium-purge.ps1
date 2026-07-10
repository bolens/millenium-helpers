# Millennium client uninstaller and files purge utility on Windows
param(
    [switch]$DryRun = $false,
    [Alias("y")]
    [switch]$Yes = $false,
    [Alias("h")]
    [switch]$Help = $false,
    [Alias("V")]
    [switch]$Version = $false
)
set-strictmode -version Latest

if ($Help) {
    Write-Host @"
Usage: millennium-purge.ps1 [-DryRun] [-Yes] [-Version] [-Help]

De-register and purge Millennium client hooks and files from Steam.

Options:
  -DryRun, -d     Simulate operations without modifying files
  -Yes, -y        Skip the interactive confirmation prompt
  -Version, -V    Show version information
  -Help, -h       Show this help message
"@
    exit 0
}

# Source shared helpers
$ScriptDir = $PSScriptRoot
$CommonPs1 = Join-Path -Path $ScriptDir -ChildPath "common.ps1"
if (Test-Path -Path $CommonPs1) {
    . $CommonPs1
} else {
    Write-Error "Shared helper library not found at $CommonPs1"
    exit 1
}

if ($Version) {
    Write-HelpersVersion -Name "millennium-purge"
    exit 0
}

if ($DryRun) {
    $global:DryRun = $true
}

$SteamPath = Resolve-SteamPath
if (!$SteamPath) {
    Log-Error "Error: Steam installation path could not be resolved."
    exit 1
}

$MillenniumDir = Join-Path -Path $SteamPath -ChildPath "millennium"
$WsockDll = Join-Path -Path $SteamPath -ChildPath "wsock32.dll"
$BackupDir = Join-Path -Path $SteamPath -ChildPath "millennium_backups"

if ($DryRun) {
    Log-Warn "=== DRY RUN MODE: No changes will be made ==="
} elseif (-not $Yes) {
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        Write-Host "${YELLOW}This will permanently remove Millennium hooks, binaries, backups, and helper config.${NC}"
        $resp = Read-Host "Are you sure you want to continue? [y/N]"
        if ($resp -notmatch '^[Yy]$') {
            Log-Info "Purge cancelled."
            exit 0
        }
    } else {
        Log-Error "Error: Refusing to purge without confirmation in a non-interactive session."
        Log-Error "Re-run with -Yes (or -y) to confirm, or use -DryRun to simulate."
        exit 1
    }
}

Log-Info "=== Initiating Millennium Purge (Uninstall) ==="

# 1. Disable scheduled tasks
$scheduleScript = Join-Path -Path $ScriptDir -ChildPath "millennium-schedule.ps1"
if ((Test-Path -Path $scheduleScript) -and (Test-Admin)) {
    Log-Info "Disabling update scheduler..."
    Execute-Cmd -ScriptBlock {
        & $scheduleScript disable
    } -Description "powershell -File $scheduleScript disable"
}

# 2. Close Steam if running
$steamRunning = $null -ne (Get-Process -Name "steam" -ErrorAction SilentlyContinue)
if ($steamRunning) {
    Capture-SteamEnv
    Close-SteamGracefully
}

# 3. Remove Millennium binaries and hook DLLs
Log-Info "Removing Millennium binaries and bootstrap files..."

if (Test-Path -Path $MillenniumDir) {
    Log-Info "Deleting folder: $MillenniumDir"
    Execute-Cmd -ScriptBlock {
        Remove-Item -Path $MillenniumDir -Recurse -Force
    } -Description "Remove-Item -Path $MillenniumDir -Recurse -Force"
}

if (Test-Path -Path $WsockDll) {
    Log-Info "Deleting file: $WsockDll"
    Execute-Cmd -ScriptBlock {
        Remove-Item -Path $WsockDll -Force
    } -Description "Remove-Item -Path $WsockDll -Force"
}

if (Test-Path -Path $BackupDir) {
    Log-Info "Deleting backups folder: $BackupDir"
    Execute-Cmd -ScriptBlock {
        Remove-Item -Path $BackupDir -Recurse -Force
    } -Description "Remove-Item -Path $BackupDir -Recurse -Force"
}

# 4. Remove config
$configDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
if (Test-Path -Path $configDir) {
    Log-Info "Deleting configurations folder: $configDir"
    Execute-Cmd -ScriptBlock {
        Remove-Item -Path $configDir -Recurse -Force
    } -Description "Remove-Item -Path $configDir -Recurse -Force"
}

if ($steamRunning) {
    Relaunch-Steam
}

Log-Info "Millennium Purge completed successfully."
exit 0
