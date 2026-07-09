# Install/Uninstall script for Millennium Helpers on Windows
param (
    [switch]$Uninstall,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Define install location
$installDir = Join-Path -Path $env:USERPROFILE -ChildPath ".millennium-helpers"
$binDir = Join-Path -Path $installDir -ChildPath "bin"

# Determine if running in an interactive console
$isInteractive = $false
try {
    $isInteractive = ([System.Console]::IsInputRedirected -eq $false)
} catch {
    $isInteractive = $false
}

# ANSI colors
$green = [char]27 + "[32m"
$yellow = [char]27 + "[33m"
$red = [char]27 + "[31m"
$cyan = [char]27 + "[36m"
$reset = [char]27 + "[0m"

function Log-Info ($msg) {
    Write-Host "${green}[INFO]${reset} $msg"
}

function Log-Warn ($msg) {
    Write-Host "${yellow}[WARN]${reset} $msg"
}

function Log-Error ($msg) {
    Write-Host "${red}[ERROR]${reset} $msg" -ErrorAction SilentlyContinue
}

if ($Uninstall) {
    Log-Info "Starting uninstallation of Millennium Helpers..."

    # Remove from PATH
    if ($IsWindows) {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -like "*$binDir*") {
            $paths = $userPath -split ";" | Where-Object { $_.Trim() -ne $binDir -and $_.Trim() -ne "" }
            $newUserPath = $paths -join ";"
            [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
            Log-Info "Removed $binDir from User PATH environment variable."
        }
    }

    if (Test-Path -Path $installDir) {
        try {
            Remove-Item -Path $installDir -Recurse -Force
            Log-Info "Removed installation directory: $installDir"
        } catch {
            Log-Warn "Could not fully remove $installDir. Some files may be in use."
        }
    }

    Log-Info "Millennium Helpers uninstallation complete."
    exit 0
}

Log-Info "Starting installation of Millennium Helpers..."

# Determine source directory
$scriptDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$srcDir = $scriptDir
if ($scriptDir -like "*windows*") {
    $srcDir = $scriptDir
} else {
    $srcDir = Join-Path -Path $scriptDir -ChildPath "scripts\windows"
}

if (!(Test-Path -Path (Join-Path -Path $srcDir -ChildPath "common.ps1"))) {
    Log-Error "Could not locate source scripts. Please run this installer from the repository source folder."
    exit 1
}

# Create directories
if (!(Test-Path -Path $binDir)) {
    New-Item -Path $binDir -ItemType Directory -Force | Out-Null
    Log-Info "Created directory: $binDir"
}

# Copy scripts
$scriptsToCopy = @(
    "common.ps1",
    "millennium-diag.ps1",
    "millennium-purge.ps1",
    "millennium-repair.ps1",
    "millennium-schedule.ps1",
    "millennium-theme.ps1",
    "millennium-upgrade.ps1"
)

foreach ($script in $scriptsToCopy) {
    $srcFile = Join-Path -Path $srcDir -ChildPath $script
    $destFile = Join-Path -Path $binDir -ChildPath $script
    Copy-Item -Path $srcFile -Destination $destFile -Force
    Log-Info "Installed: $script"
}

# Generate CMD wrappers
$wrappers = @(
    "millennium-diag",
    "millennium-purge",
    "millennium-repair",
    "millennium-schedule",
    "millennium-theme",
    "millennium-upgrade"
)

foreach ($wrapperName in $wrappers) {
    $wrapperPath = Join-Path -Path $binDir -ChildPath "$wrapperName.cmd"
    $cmdContent = @"
@echo off
where pwsh >nul 2>nul
if %ERRORLEVEL% equ 0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0$wrapperName.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0$wrapperName.ps1" %*
)
"@
    Set-Content -Path $wrapperPath -Value $cmdContent -Encoding ASCII
    Log-Info "Created wrapper command: $wrapperName"
}

# Add to PATH
if ($IsWindows) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$binDir*") {
        $newUserPath = $userPath
        if ($newUserPath -and !$newUserPath.EndsWith(";")) {
            $newUserPath += ";"
        }
        $newUserPath += $binDir
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Log-Info "Added $binDir to User PATH environment variable."
        Log-Warn "Please restart your terminal or environment for the PATH changes to take effect."
    } else {
        Log-Info "$binDir is already in User PATH."
    }
} else {
    Log-Info "Skipping Registry-based PATH update (only supported on Windows)."
}

Log-Info "${green}Millennium Helpers successfully installed!${reset}"

# Launch configuration wizard if running interactively
if ($isInteractive -and !$Uninstall -and $env:PSTESTS -ne "true") {
    Log-Info "Launching the Millennium Helpers Configuration Wizard..."
    & (Join-Path -Path $binDir -ChildPath "millennium-schedule.ps1") setup
}

Log-Info "You can now run commands like: ${cyan}millennium-diag${reset} or ${cyan}millennium-upgrade${reset} from any terminal."
