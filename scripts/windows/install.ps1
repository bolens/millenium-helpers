# Install/Uninstall script for Millennium Helpers on Windows
param (
    [switch]$Uninstall,
    [switch]$Force,
    [switch]$Help,
    [switch]$Version,
    [switch]$DryRun,
    [ValidateSet('release', 'main', 'tag', '')]
    [string]$Track = '',
    [string]$Tag = '',
    [switch]$AllowUnsignedMain
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host @"
Usage: install.ps1 [-Uninstall] [-Track release|main] [-Tag vX.Y.Z] [-AllowUnsignedMain] [-DryRun] [-Force] [-Version] [-Help]

  -Track   Helpers install track: release (default), main (tip-of-main)
  -Tag     Install a specific release tag (implies -Track tag)
  -AllowUnsignedMain  Required with -Track main (no SHA256 sidecar)
  -Force   Reinstall over an existing installation
  -DryRun  Show actions without writing files

Environment: MILLENNIUM_HELPERS_TRACK, MILLENNIUM_HELPERS_TAG,
  MILLENNIUM_HELPERS_RELEASE_URL, MILLENNIUM_HELPERS_RELEASE_SHA_URL,
  MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN=1

Install requires millennium.exe (Go dispatcher) on PATH.

Release checksums are same-origin GitHub TOFU, not independent signing.

Millennium client update channel (stable|beta|main) is separate — use
millennium-schedule / millennium-upgrade -Channel.
"@
    return
}

# Resolve script path early for version / standalone detection
$scriptPath = ""
if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Definition) {
    $scriptPath = $MyInvocation.MyCommand.Definition
}

if ($Version) {
    $verCandidates = @()
    if ($scriptPath) {
        $sd = Split-Path -Parent -Path $scriptPath
        $verCandidates += (Join-Path $sd '..\..\VERSION')
        $verCandidates += (Join-Path $sd 'VERSION')
    }
    $verCandidates += (Join-Path $env:USERPROFILE '.millennium-helpers\bin\VERSION')
    foreach ($vc in $verCandidates) {
        if (Test-Path -LiteralPath $vc -PathType Leaf) {
            Write-Host ((Get-Content -LiteralPath $vc -Raw).Trim())
            return
        }
    }
    Write-Host "unknown"
    return
}

if (-not [string]::IsNullOrWhiteSpace($Tag)) {
    $Track = 'tag'
}
if ([string]::IsNullOrWhiteSpace($Track)) {
    $Track = if ($env:MILLENNIUM_HELPERS_TRACK) { $env:MILLENNIUM_HELPERS_TRACK } else { 'release' }
}
$Track = $Track.ToLowerInvariant()

# If running standalone/piped (e.g. via Invoke-Expression), download archive and re-exec
$isStandalone = $true
if ($scriptPath -and (Test-Path -Path $scriptPath -PathType Leaf)) {
    $scriptDir = Split-Path -Parent -Path $scriptPath
    $testCommon = Join-Path -Path $scriptDir -ChildPath "common.ps1"
    if (!(Test-Path -Path $testCommon)) {
        $testCommon = Join-Path -Path $scriptDir -ChildPath "scripts\windows\common.ps1"
    }
    if (Test-Path -Path $testCommon) {
        $isStandalone = $false
    }
}

if ($isStandalone) {
    Write-Host "Running in standalone/piped mode. Downloading helpers (track=$Track)..."
    $tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "millennium-helpers-temp"
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    $repo = if ($env:HELPERS_GITHUB_REPO) { $env:HELPERS_GITHUB_REPO } else { 'bolens/millenium-helpers' }
    $needsSha = $true
    $isSource = $false
    if ($env:MILLENNIUM_HELPERS_RELEASE_URL) {
        Write-Host "Warning: MILLENNIUM_HELPERS_RELEASE_URL overrides the download source (and matching SHA if provided)."
        $url = $env:MILLENNIUM_HELPERS_RELEASE_URL
        $shaUrl = if ($env:MILLENNIUM_HELPERS_RELEASE_SHA_URL) { $env:MILLENNIUM_HELPERS_RELEASE_SHA_URL } else { "$url.sha256" }
    } else {
        switch ($Track) {
            'main' {
                $allowMain = $AllowUnsignedMain -or ($env:MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN -eq '1')
                if (-not $allowMain) {
                    throw "Track main installs an unsigned tip-of-main archive. Pass -AllowUnsignedMain (or set MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN=1). Prefer -Track release or -Tag vX.Y.Z."
                }
                Write-Host "Warning: tip-of-main install has no SHA256 sidecar (unsigned)."
                $url = "https://github.com/$repo/archive/refs/heads/main.zip"
                $shaUrl = ''
                $needsSha = $false
                $isSource = $true
            }
            'tag' {
                if ([string]::IsNullOrWhiteSpace($Tag) -and $env:MILLENNIUM_HELPERS_TAG) { $Tag = $env:MILLENNIUM_HELPERS_TAG }
                if ([string]::IsNullOrWhiteSpace($Tag)) { throw "Tag is required for -Track tag" }
                $norm = if ($Tag.StartsWith('v')) { $Tag } else { "v$Tag" }
                $ver = $norm.TrimStart('v')
                $url = "https://github.com/$repo/releases/download/$norm/millennium-helpers-v$ver-windows-amd64.zip"
                $shaUrl = "$url.sha256"
            }
            default {
                $headers = @{ 'User-Agent' = 'millennium-helpers'; 'Accept' = 'application/vnd.github+json' }
                $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $headers -UseBasicParsing
                $norm = [string]$release.tag_name
                if ([string]::IsNullOrWhiteSpace($norm)) { throw "Could not resolve latest release tag for $repo" }
                $ver = $norm.TrimStart('v')
                $url = "https://github.com/$repo/releases/download/$norm/millennium-helpers-v$ver-windows-amd64.zip"
                $shaUrl = "$url.sha256"
            }
        }
    }

    $zipPath = Join-Path -Path $tempDir -ChildPath "millennium-helpers-download.zip"
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

    if ($needsSha) {
        $shaPath = Join-Path -Path $tempDir -ChildPath "millennium-helpers-download.zip.sha256"
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
    } else {
        Write-Host "Tip-of-main archive: skipping release SHA256 sidecar."
    }

    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

    $extractedScript = Join-Path -Path $tempDir -ChildPath "scripts\windows\install.ps1"
    if (!(Test-Path -Path $extractedScript -PathType Leaf)) {
        $extractedFolder = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
        if ($extractedFolder) {
            $extractedScript = Join-Path -Path $extractedFolder.FullName -ChildPath "scripts\windows\install.ps1"
        }
    }
    if (!(Test-Path -Path $extractedScript -PathType Leaf)) {
        throw "Archive is missing scripts\windows\install.ps1 (url=$url)"
    }

    $env:MILLENNIUM_HELPERS_TRACK = $Track
    if ($Tag) { $env:MILLENNIUM_HELPERS_TAG = $Tag }
    $env:MILLENNIUM_HELPERS_SOURCE_URL = $url

    $params = @{}
    if ($PSBoundParameters.ContainsKey("Uninstall")) { $params["Uninstall"] = $Uninstall }
    if ($PSBoundParameters.ContainsKey("Force")) { $params["Force"] = $Force }
    if ($PSBoundParameters.ContainsKey("DryRun")) { $params["DryRun"] = $DryRun }
    if ($Track) { $params["Track"] = $Track }
    if ($Tag) { $params["Tag"] = $Tag }

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

if ($DryRun) {
    Log-Warn "DRY RUN: no files will be written"
    Log-Info "Would install to $binDir (track=$Track$(if ($Tag) { ", tag=$Tag" } else { '' }))"
    Log-Info "Would require millennium.exe (Go dispatcher)"
    return
}

$existingDispatch = Test-Path (Join-Path $binDir 'millennium.exe')
if ((Test-Path -Path $binDir) -and -not $Force -and $existingDispatch) {
    Log-Warn "Existing installation found at $binDir. Re-run with -Force to overwrite."
}

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

# Require Go dispatcher (millennium.exe) — no PowerShell PATH dispatcher.
$exeCandidates = @(
    (Join-Path -Path $srcDir -ChildPath 'millennium.exe'),
    (Join-Path -Path $srcDir -ChildPath '..\..\bin\millennium.exe'),
    (Join-Path -Path $srcDir -ChildPath 'bin\millennium.exe')
)
$installedExe = $false
foreach ($exeSrc in $exeCandidates) {
    if (Test-Path -LiteralPath $exeSrc -PathType Leaf) {
        Copy-Item -Path $exeSrc -Destination (Join-Path -Path $binDir -ChildPath 'millennium.exe') -Force
        Log-Info "Installed: millennium.exe (Go dispatcher)"
        $installedExe = $true
        break
    }
}
if (-not $installedExe) {
    $repoRoot = (Resolve-Path (Join-Path -Path $srcDir -ChildPath '..\..')).Path
    $goCmd = Get-Command go -ErrorAction SilentlyContinue
    $goMain = Join-Path -Path $repoRoot -ChildPath 'go\cmd\millennium'
    if ($goCmd -and (Test-Path -LiteralPath $goMain)) {
        $outExe = Join-Path -Path $repoRoot -ChildPath 'bin\millennium.exe'
        $binOutDir = Split-Path -Parent -Path $outExe
        if (!(Test-Path -LiteralPath $binOutDir)) {
            New-Item -ItemType Directory -Force -Path $binOutDir | Out-Null
        }
        Log-Info "Building Go dispatcher (bin\millennium.exe)..."
        Push-Location (Join-Path -Path $repoRoot -ChildPath 'go')
        try {
            & go build -o $outExe ./cmd/millennium
            if ($LASTEXITCODE -ne 0) { throw "go build failed" }
        } finally {
            Pop-Location
        }
        if (Test-Path -LiteralPath $outExe -PathType Leaf) {
            Copy-Item -Path $outExe -Destination (Join-Path -Path $binDir -ChildPath 'millennium.exe') -Force
            Log-Info "Installed: millennium.exe (Go dispatcher)"
            $installedExe = $true
        }
    }
}
if (-not $installedExe) {
    Log-Error "Go dispatcher (millennium.exe) is required to install PATH millennium."
    Log-Error "Place bin\millennium.exe (release archive / make build), or install a Go toolchain and re-run."
    exit 1
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

# Vendored Millennium client MIT license (installed next to the client on upgrade)
$licenseCandidates = @(
    (Join-Path -Path $srcDir -ChildPath "..\..\third_party\MILLENNIUM-LICENSE.md"),
    (Join-Path -Path $srcDir -ChildPath "third_party\MILLENNIUM-LICENSE.md"),
    (Join-Path -Path $srcDir -ChildPath "MILLENNIUM-LICENSE.md")
)
foreach ($licSrc in $licenseCandidates) {
    if (Test-Path -Path $licSrc -PathType Leaf) {
        Copy-Item -Path $licSrc -Destination (Join-Path -Path $binDir -ChildPath "MILLENNIUM-LICENSE.md") -Force
        Log-Info "Installed: MILLENNIUM-LICENSE.md"
        break
    }
}

# Write install-meta.json for track-aware doctor/updates
$trackLib = Join-Path -Path $srcDir -ChildPath 'lib\InstallTrack.ps1'
if (Test-Path -LiteralPath $trackLib) {
    . $trackLib
    $metaTrack = $Track
    $metaRef = 'latest'
    $metaVer = ''
    $verInstalled = Join-Path -Path $binDir -ChildPath 'VERSION'
    if (Test-Path -LiteralPath $verInstalled) {
        $metaVer = (Get-Content -LiteralPath $verInstalled -Raw).Trim()
    }
    $sourceUrl = if ($env:MILLENNIUM_HELPERS_SOURCE_URL) { $env:MILLENNIUM_HELPERS_SOURCE_URL } else { '' }
    $repoRoot = Join-Path -Path $srcDir -ChildPath '..\..'
    if ($metaTrack -eq 'release' -and -not $sourceUrl -and (Test-Path (Join-Path $repoRoot '.git'))) {
        $metaTrack = 'checkout'
    }
    switch ($metaTrack) {
        'tag' {
            $t = if ($Tag) { $Tag } elseif ($env:MILLENNIUM_HELPERS_TAG) { $env:MILLENNIUM_HELPERS_TAG } else { $metaVer }
            $metaRef = if ($t -and $t.StartsWith('v')) { $t } elseif ($t) { "v$t" } else { 'latest' }
        }
        'main' {
            $sha = Get-HelpersMainCommitSha
            $metaRef = if ($sha) { $sha } else { 'main' }
        }
        'checkout' {
            try {
                $metaRef = (git -C $repoRoot rev-parse --short HEAD 2>$null)
                if (-not $metaRef) { $metaRef = 'checkout' }
            } catch { $metaRef = 'checkout' }
        }
        default {
            $metaTrack = 'release'
            $metaRef = if ($metaVer) { "v$metaVer" } else { 'latest' }
        }
    }
    Write-HelpersInstallMeta -InstallRoot $installDir -Track $metaTrack -Ref $metaRef -Version $metaVer -SourceUrl $sourceUrl
    Log-Info "Installed: install-meta.json (track=$metaTrack)"
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
    $hasExe = Test-Path (Join-Path $binDir 'millennium.exe')
    if ($wrapperName -eq 'millennium' -and $hasExe) {
        $cmdContent = @"
@echo off
"%~dp0millennium.exe" %*
"@
    } elseif ($wrapperName -eq 'millennium-mcp' -and $hasExe) {
        $cmdContent = @"
@echo off
"%~dp0millennium.exe" mcp %*
"@
    } else {
        $cmdContent = @"
@echo off
where pwsh >nul 2>nul
if %ERRORLEVEL% equ 0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0$wrapperName.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0$wrapperName.ps1" %*
)
"@
    }
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
