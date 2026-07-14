# Diagnostics and status reporter for Millennium helper scripts on Windows
param(
    [string]$Command = $null,
    [switch]$Force   = $false,
    [switch]$Json    = $false,
    [switch]$DryRun  = $false,
    [switch]$Share   = $false,
    [Alias("l")]
    [switch]$Follow  = $false,
    [Alias("y")]
    [switch]$Yes     = $false,
    [Alias("q")]
    [switch]$Quiet   = $false,
    [Alias("h")]
    [switch]$Help    = $false,
    [Alias("V")]
    [switch]$Version = $false
)
Set-StrictMode -Version Latest

# Source shared helpers
$DiagScriptRoot = $PSScriptRoot
$ScriptDir      = $DiagScriptRoot
$CommonPs1 = Join-Path -Path $DiagScriptRoot -ChildPath 'common.ps1'
if (Test-Path -Path $CommonPs1) {
    . $CommonPs1
} else {
    Write-Error "Shared helper library not found at $CommonPs1"
    exit 1
}

# --- Help / Version (early exit before loading diag lib) ---
if ($Help -or $Command -eq 'help' -or $Command -eq '--help' -or $Command -eq '-h') {
    Write-Output @"
Usage: millennium-diag [COMMAND] [OPTIONS]

Commands:
  (None)        Run read-only diagnostics report (default)
  doctor        Detect and repair issues (cleanup first; never overwrites Scoop/Winget installs)
  logs          Display recent Millennium and Steam WebHelper startup logs

Options:
  -Force        Force all doctor repairs even if system is healthy
  -Json         Structured JSON (includes install_method, scripts_up_to_date, ...)
  -DryRun       Simulate doctor repairs without modifying anything
  -Share        Upload diagnostic report to a pastebin and return a short link
  -Follow, -l   Follow (tail -f) real-time log output
  -Yes, -y      Skip Steam close prompt; auto-run scoop/winget upgrade when packaged
  -Quiet, -q    Suppress informational output
  -Version, -V  Show version information
  -Help, -h     Show this help message

Detects scoop / winget / manual / mixed installs. Packaged installs compare VERSION
to the latest GitHub release; manual installs sync from the release zip.
"@
    exit 0
}
if ($Version -or $Command -eq 'version' -or $Command -eq '--version' -or $Command -eq '-V') {
    Write-HelpersVersion -Name 'millennium-diag'
    exit 0
}

# --- CLI flag globals (initialize unconditionally for StrictMode compatibility) ---
$global:AssumeYes = [bool]$Yes
$global:Quiet     = [bool]$Quiet
$global:DryRun    = [bool]$DryRun
$global:Force     = [bool]$Force
if ($Quiet) { $env:MILLENNIUM_QUIET = '1' }

# Support command aliases from positional args
if ($args.Count -gt 0) {
    if ($args[0] -eq 'doctor' -or $args[0] -eq '-f' -or $args[0] -eq '--fix') {
        $Command = 'doctor'
    } elseif ($args[0] -eq 'logs') {
        $Command = 'logs'
    }
}

# --- Share: capture report output, redact, upload ---
if ($Share) {
    Write-Host 'Generating and uploading diagnostic report...'
    $cleanArgs = @()
    if ($Json)    { $cleanArgs += '-Json' }
    if ($DryRun)  { $cleanArgs += '-DryRun' }
    if ($Force)   { $cleanArgs += '-Force' }
    if ($Yes)     { $cleanArgs += '-Yes' }
    if ($Command) { $cleanArgs += $Command }
    $reportOutput = & $PSCommandPath @cleanArgs *>&1 | Out-String

    $userName    = $env:USERNAME
    $userProfile = $env:USERPROFILE
    if ($userProfile) { $reportOutput = $reportOutput -replace [regex]::Escape($userProfile), '~' }
    if ($userName)    { $reportOutput = $reportOutput -replace $userName, 'user' }
    $reportOutput = $reportOutput -replace 'ghp_[A-Za-z0-9_]+', '[REDACTED]'
    $reportOutput = $reportOutput -replace 'github_pat_[A-Za-z0-9_]+', '[REDACTED]'

    $configFile = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'millennium-helpers\config.json'
    if (Test-Path -Path $configFile) {
        try {
            $configObj = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            if ($configObj -and $configObj.github_token -and $configObj.github_token.Length -ge 4) {
                $reportOutput = $reportOutput -replace [regex]::Escape($configObj.github_token), '[REDACTED]'
            }
        } catch { }
    }
    if ($env:GITHUB_TOKEN -and $env:GITHUB_TOKEN.Length -ge 4) {
        $reportOutput = $reportOutput -replace [regex]::Escape($env:GITHUB_TOKEN), '[REDACTED]'
    }

    try {
        $response = Invoke-RestMethod -Uri 'https://paste.rs' -Method Post `
            -Body $reportOutput -ContentType 'text/plain; charset=utf-8'
        if ($response -and $response -like '*http*') {
            Write-Host -ForegroundColor Green 'Diagnostic report successfully shared!'
            Write-Host -NoNewline 'URL: '
            Write-Host -ForegroundColor Blue $response.Trim()
        } else {
            Write-Error "Error: Failed to upload diagnostic report to paste.rs. (Invalid response: $response)"
            $tmp = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
                -ChildPath ("millennium-diag-" + [guid]::NewGuid().ToString("n") + ".txt")
            Set-Content -Path $tmp -Value $reportOutput -Encoding UTF8
            Write-Host "Local sanitized report kept at: $tmp"
            Write-Host 'Tip: retry later, or paste the file contents into an offline pastebin.'
            exit 1
        }
    } catch {
        Write-Error "Error: Failed to upload diagnostic report to paste.rs. ($($_.Exception.Message))"
        $tmp = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
            -ChildPath ("millennium-diag-" + [guid]::NewGuid().ToString("n") + ".txt")
        Set-Content -Path $tmp -Value $reportOutput -Encoding UTF8
        Write-Host "Local sanitized report kept at: $tmp"
        Write-Host 'Tip: retry later, or paste the file contents into an offline pastebin.'
        exit 1
    }
    exit 0
}

# --- Load diagnostic modules (no thin aggregator) ---
$script:DiagLibDir = Join-Path -Path $DiagScriptRoot -ChildPath 'lib'
$script:ScriptDir  = $DiagScriptRoot
$script:Channel    = 'stable'
$script:VersionStr = 'Not Installed'
$script:SteamPath  = ''
$script:MillenniumDir = ''
$script:WsockDll   = ''
$script:SkinsDir   = ''

$diagModules = @(
    'DiagUi.ps1',
    'DiagSteam.ps1',
    'DiagEnv.ps1',
    'DiagCompletions.ps1',
    'DiagInstall.ps1',
    'DiagRelease.ps1',
    'DiagUpdates.ps1',
    'DiagNextSteps.ps1',
    'DiagDoctorCleanup.ps1',
    'DiagDoctorRepair.ps1',
    'DiagDoctor.ps1',
    'DiagReport.ps1'
)
foreach ($mod in $diagModules) {
    $modPath = Join-Path -Path $script:DiagLibDir -ChildPath $mod
    if (-not (Test-Path -Path $modPath)) {
        Write-Error "Diagnostic library module not found at $modPath"
        exit 1
    }
    . $modPath
}

# --- Resolve Steam path ---
# $env:DIAG_TEST_STEAM_PATH lets test environments skip registry lookups on Linux CI.
if ($env:DIAG_TEST_STEAM_PATH) {
    $script:SteamPath = $env:DIAG_TEST_STEAM_PATH
} else {
    $script:SteamPath = Resolve-SteamPath
}

# --- Logs viewer ---
if ($Command -eq 'logs') {
    $helpersStateDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'millennium-helpers'
    $updaterLog      = Join-Path -Path $helpersStateDir  -ChildPath 'updater.log'
    if (Test-Path -Path $updaterLog) {
        Write-Host -ForegroundColor Blue '=== Millennium Background Auto-Updater Logs ==='
        Get-Content -Path $updaterLog -Tail 50 -ErrorAction SilentlyContinue
        Write-Host ''
    }

    Write-Host -ForegroundColor Blue '=== Millennium & Steam WebHelper Logs ==='

    if (!$script:SteamPath) {
        Log-Error 'Error: Steam installation path could not be resolved.'
        exit 1
    }

    $steamLogsDir = Join-Path -Path $script:SteamPath -ChildPath 'logs'
    $logNames     = @('webhelper.txt','console_log.txt','console.txt','content_log.txt','stderr.txt','stdout.txt')
    $logFiles     = @()
    foreach ($logName in $logNames) {
        $candidate = Join-Path -Path $steamLogsDir -ChildPath $logName
        if (Test-Path -Path $candidate -PathType Leaf) { $logFiles += Get-Item -Path $candidate }
    }

    if ($logFiles.Count -eq 0) {
        Log-Error "Error: No Steam logs found under $steamLogsDir."
        exit 1
    }

    $latestLog = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host -ForegroundColor Yellow "Reading log file: $($latestLog.FullName)`n"

    $filterRegex = 'Millennium|BOOTSTRAP|update-check|plugin_loader|steamwebhelper|wsock32'
    if ($Follow) {
        Write-Host 'Tailing log file (Ctrl+C to exit)...'
        Get-Content -Path $latestLog.FullName -Tail 100 -Wait |
            Where-Object { $_ -match $filterRegex }
    } else {
        $logMatches = Get-Content -Path $latestLog.FullName -Tail 200 -ErrorAction SilentlyContinue |
            Where-Object { $_ -match $filterRegex }
        if ($logMatches) { $logMatches | ForEach-Object { Write-Host $_ } }
        else { Write-Host 'No recent Millennium-related log entries found.' }
    }
    exit 0
}

# --- Initialize remaining shared script state for diag modules ---
$script:Channel    = 'stable'
$script:VersionStr = 'Not Installed'
$script:ScriptDir  = $DiagScriptRoot

$configFile2 = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'millennium-helpers\config.json'
if (Test-Path -Path $configFile2) {
    try {
        $config = Get-Content -Path $configFile2 -Raw | ConvertFrom-Json
        if ($config -and $config.update_channel) { $script:Channel = $config.update_channel }
    } catch { }
}

if (!$script:SteamPath) {
    Log-Error 'Error: Steam installation path could not be resolved.'
    exit 1
}

$script:MillenniumDir = Join-Path -Path $script:SteamPath -ChildPath 'millennium'
$script:WsockDll      = Join-Path -Path $script:SteamPath -ChildPath 'wsock32.dll'
$script:SkinsDir      = Join-Path -Path $script:SteamPath -ChildPath 'steamui\skins'

# --- Run all diagnostics checks (populates $script: state, no output) ---
Invoke-DiagnosticsChecks

# --- Output: JSON or human-readable ---
if ($Json) {
    Get-DiagJsonObject | ConvertTo-Json
    exit 0
}

Write-DiagReport

if ($Command -ne 'doctor') {
    Print-DiagNextSteps
}

# --- Doctor ---
if ($Command -eq 'doctor') {
    Invoke-DoctorRepairs
}

exit 0
