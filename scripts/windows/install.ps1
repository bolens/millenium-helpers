# Install/Uninstall script for Millennium Helpers on Windows
param (
    [switch]$Uninstall,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# If running standalone/piped (e.g. via Invoke-Expression), download the full repository zip to temp and run
$scriptPath = ""
if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Definition) {
    $scriptPath = $MyInvocation.MyCommand.Definition
}

$isStandalone = $true
if ($scriptPath -and (Test-Path -Path $scriptPath -PathType Leaf)) {
    $scriptDir = Split-Path -Parent -Path $scriptPath
    # Check if we are running in the repo or near scripts
    $testCommon = Join-Path -Path $scriptDir -ChildPath "common.ps1"
    if (!(Test-Path -Path $testCommon)) {
        # Check if we are in the root of the repo
        $testCommon = Join-Path -Path $scriptDir -ChildPath "scripts\windows\common.ps1"
    }
    if (Test-Path -Path $testCommon) {
        $isStandalone = $false
    }
}

if ($isStandalone) {
    Write-Host "Running in standalone/piped mode. Downloading latest Windows release..."
    $tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "millennium-helpers-temp"
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    $zipPath = Join-Path -Path $tempDir -ChildPath "millennium-helpers-windows.zip"
    $url = if ($env:MILLENNIUM_HELPERS_RELEASE_URL) {
        $env:MILLENNIUM_HELPERS_RELEASE_URL
    } else {
        "https://github.com/bolens/millenium-helpers/releases/latest/download/millennium-helpers-windows.zip"
    }
    $shaUrl = if ($env:MILLENNIUM_HELPERS_RELEASE_SHA_URL) {
        $env:MILLENNIUM_HELPERS_RELEASE_SHA_URL
    } else {
        "$url.sha256"
    }

    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

    $shaPath = Join-Path -Path $tempDir -ChildPath "millennium-helpers-windows.zip.sha256"
    try {
        Invoke-WebRequest -Uri $shaUrl -OutFile $shaPath -UseBasicParsing
    } catch {
        throw "Failed to download the SHA256 checksum sidecar (url=$shaUrl): $_"
    }
    if (!(Test-Path -Path $shaPath -PathType Leaf)) {
        throw "SHA256 checksum sidecar was not downloaded (url=$shaUrl)"
    }
    $expectedSha = ((Get-Content -Path $shaPath -Raw).Trim() -split '\s+')[0]
    if ([string]::IsNullOrWhiteSpace($expectedSha) -or $expectedSha -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Checksum sidecar did not contain a valid SHA256 hash (url=$shaUrl)"
    }
    $actualSha = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
    if ($actualSha.ToLowerInvariant() -ne $expectedSha.ToLowerInvariant()) {
        throw "SHA256 mismatch for downloaded release archive. Expected=$expectedSha Actual=$actualSha"
    }
    Write-Host "SHA256 checksum verified."

    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

    $extractedScript = Join-Path -Path $tempDir -ChildPath "scripts\windows\install.ps1"
    if (!(Test-Path -Path $extractedScript -PathType Leaf)) {
        # Older source-archive layout used a single top-level folder.
        $extractedFolder = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
        if ($extractedFolder) {
            $extractedScript = Join-Path -Path $extractedFolder.FullName -ChildPath "scripts\windows\install.ps1"
        }
    }
    if (!(Test-Path -Path $extractedScript -PathType Leaf)) {
        throw "Release archive is missing scripts\windows\install.ps1 (url=$url)"
    }

    $params = @{}
    if ($PSBoundParameters.ContainsKey("Uninstall")) { $params["Uninstall"] = $Uninstall }
    if ($PSBoundParameters.ContainsKey("Force")) { $params["Force"] = $Force }

    & $extractedScript @params

    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    return
}

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

    # Remove daily auto-update scheduled task (best-effort)
    try {
        if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
            $existing = Get-ScheduledTask -TaskName "MillenniumUpdate" -ErrorAction SilentlyContinue
            if ($existing) {
                if ($env:PSTESTS -ne "true") {
                    Unregister-ScheduledTask -TaskName "MillenniumUpdate" -Confirm:$false
                }
                Log-Info "Removed scheduled task: MillenniumUpdate"
            }
        }
    } catch {
        Log-Warn "Could not remove MillenniumUpdate scheduled task: $($_.Exception.Message)"
    }

    # Remove from PATH
    if ($IsWindows) {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -like "*$binDir*") {
            $paths = $userPath -split ";" | Where-Object { $_.Trim() -ne $binDir -and $_.Trim() -ne "" }
            $newUserPath = $paths -join ";"
            if ($env:PSTESTS -ne "true") {
                [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
            } else {
                Log-Info "[TEST] Bypassed removing $binDir from User PATH registry."
            }
            Log-Info "Removed $binDir from User PATH environment variable."
        }
    }

    # Remove lib sub-directory if present (best-effort before full removal)
    $libDir2 = Join-Path -Path $binDir -ChildPath "lib"
    if (Test-Path -Path $libDir2) {
        try {
            Remove-Item -Path $libDir2 -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            Log-Info "Removed lib directory: $libDir2"
        } catch { }
    }

    if (Test-Path -Path $installDir) {
        try {
            Remove-Item -Path $installDir -Recurse -Force
            Log-Info "Removed installation directory: $installDir"
        } catch {
            Log-Warn "Could not fully remove $installDir. Some files may be in use."
        }
    }

    # Drop profile hooks that load the completer (only under this user's home)
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $profiles = @(
        (Join-Path -Path $userHome -ChildPath "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
        (Join-Path -Path $userHome -ChildPath "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
    )
    if ($PROFILE -and $PROFILE.StartsWith($userHome)) {
        $profiles = @($PROFILE) + $profiles
    }
    foreach ($profilePath in ($profiles | Select-Object -Unique)) {
        if (!(Test-Path -Path $profilePath)) { continue }
        $content = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -like "*millennium-helpers.completion.ps1*") {
            $filtered = ($content -split "`n" | Where-Object {
                $_ -notmatch 'millennium-helpers\.completion\.ps1' -and $_ -notmatch '^\s*# Millennium Helpers completions\s*$'
            }) -join "`n"
            Set-Content -Path $profilePath -Value $filtered -Encoding UTF8
            Log-Info "Removed completion hook from $profilePath"
        }
    }

    Log-Info "Millennium Helpers uninstallation complete."
    return
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
    return
}

# Create directories
if (!(Test-Path -Path $binDir)) {
    New-Item -Path $binDir -ItemType Directory -Force | Out-Null
    Log-Info "Created directory: $binDir"
}

# Copy scripts
$scriptsToCopy = @(
    "common.ps1",
    "millennium.ps1",
    "millennium-diag.ps1",
    "millennium-mcp.ps1",
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

# Install lib/*.ps1 modules (required by millennium-diag.ps1)
$libSrc  = Join-Path -Path $srcDir -ChildPath 'lib'
$libDest = Join-Path -Path $binDir -ChildPath 'lib'
if (Test-Path -Path $libSrc) {
    New-Item -ItemType Directory -Force -Path $libDest | Out-Null
    Copy-Item -Path (Join-Path -Path $libSrc -ChildPath '*.ps1') -Destination $libDest -Force
    Log-Info "Installed: lib\*.ps1 modules"
}

# Install VERSION file next to scripts for -Version lookups
$versionSrc = Join-Path -Path $srcDir -ChildPath "..\..\VERSION"
if (!(Test-Path -Path $versionSrc)) {
    $versionSrc = Join-Path -Path $srcDir -ChildPath "VERSION"
}
if (Test-Path -Path $versionSrc) {
    Copy-Item -Path $versionSrc -Destination (Join-Path -Path $binDir -ChildPath "VERSION") -Force
    Log-Info "Installed: VERSION"
}

# Also install the Python MCP server next to the PowerShell wrapper
$mcpPySrc = Join-Path -Path $srcDir -ChildPath "..\millennium-mcp.py"
if (!(Test-Path -Path $mcpPySrc)) {
    $mcpPySrc = Join-Path -Path $srcDir -ChildPath "millennium-mcp.py"
}
if (Test-Path -Path $mcpPySrc) {
    Copy-Item -Path $mcpPySrc -Destination (Join-Path -Path $binDir -ChildPath "millennium-mcp.py") -Force
    Log-Info "Installed: millennium-mcp.py"
}

# Generate CMD wrappers
$wrappers = @(
    "millennium",
    "millennium-diag",
    "millennium-mcp",
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

# Install PowerShell argument completers next to the scripts
$completionSrc = Join-Path -Path $srcDir -ChildPath "..\..\completions\powershell\millennium-helpers.ps1"
if (!(Test-Path -Path $completionSrc)) {
    $completionSrc = Join-Path -Path $srcDir -ChildPath "millennium-helpers.completion.ps1"
}
$completionDest = Join-Path -Path $binDir -ChildPath "millennium-helpers.completion.ps1"
if (Test-Path -Path $completionSrc) {
    Copy-Item -Path $completionSrc -Destination $completionDest -Force
    Log-Info "Installed: millennium-helpers.completion.ps1"

    # Register a profile hook so Tab completion works in new sessions.
    # Only touch profiles under the install user's home (respects USERPROFILE overrides in tests).
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $profiles = @(
        (Join-Path -Path $userHome -ChildPath "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
        (Join-Path -Path $userHome -ChildPath "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
    )
    if ($PROFILE -and $PROFILE.StartsWith($userHome)) {
        $profiles = @($PROFILE) + $profiles
    }
    $profiles = $profiles | Select-Object -Unique
    $hook = ". `"$completionDest`""
    foreach ($profilePath in $profiles) {
        if ([string]::IsNullOrWhiteSpace($profilePath)) { continue }
        $profileDir = Split-Path -Parent -Path $profilePath
        if (!(Test-Path -Path $profileDir)) {
            New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
        }
        $existing = ""
        if (Test-Path -Path $profilePath) {
            $existing = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
        }
        if ($existing -notlike "*millennium-helpers.completion.ps1*") {
            Add-Content -Path $profilePath -Value "`n# Millennium Helpers completions`n$hook`n"
            Log-Info "Registered PowerShell completion hook in $profilePath"
        }
    }
} else {
    Log-Warn "PowerShell completion script not found; Tab completions were not installed."
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
        if ($env:PSTESTS -ne "true") {
            [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        } else {
            Log-Info "[TEST] Bypassed adding $binDir to User PATH registry."
        }
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

Write-Host ""
Write-Host "${cyan}Getting started:${reset}"
Write-Host "  1. Check health:     ${green}millennium diag${reset}"
Write-Host "  2. Install/update:   ${green}millennium upgrade${reset}   (if Millennium is missing)"
Write-Host "  3. Review scheduler: ${green}millennium schedule status${reset}"
Write-Host "  Tip: manage skins with ${green}millennium theme list${reset}"
Write-Host ""
Write-Host "Long names (millennium-diag, ...) still work as aliases."
Write-Host "Dispatcher: ${cyan}millennium diag|upgrade|doctor|schedule|theme|...${reset}"
