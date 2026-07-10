# PowerShell script to upgrade or reinstall the Millennium client on Windows
param(
    [ValidateSet("stable", "beta", "main")]
    [string]$Channel = "stable",
    [switch]$Force = $false,
    [string]$File = $null,
    [string]$Rollback = $null,
    [switch]$DryRun = $false,
    [Alias("y")]
    [switch]$Yes = $false,
    [Alias("q")]
    [switch]$Quiet = $false,
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

# GNU-style flags (--main, --channel, --force, …) from unbound args
$channelExplicit = $MyInvocation.BoundParameters.ContainsKey('Channel')
if ($args.Count -gt 0) {
    $gnuFlags = @{
        Channel  = $null
        Force    = [bool]$Force
        File     = $File
        Rollback = $Rollback
        DryRun   = [bool]$DryRun
        Yes      = [bool]$Yes
        Quiet    = [bool]$Quiet
        Help     = [bool]$Help
        Version  = [bool]$Version
    }
    [void](Apply-GnuStyleArgs -InputArgs ([string[]]$args) -Target $gnuFlags)
    if ($null -ne $gnuFlags.Channel -and "$($gnuFlags.Channel)" -ne "") {
        $Channel = [string]$gnuFlags.Channel
        $channelExplicit = $true
    }
    if ($gnuFlags.Force) { $Force = $true }
    if ($gnuFlags.File) { $File = [string]$gnuFlags.File }
    if ($gnuFlags.Rollback) { $Rollback = [string]$gnuFlags.Rollback }
    if ($gnuFlags.DryRun) { $DryRun = $true }
    if ($gnuFlags.Yes) { $Yes = $true }
    if ($gnuFlags.Quiet) { $Quiet = $true; $global:Quiet = $true; $env:MILLENNIUM_QUIET = "1" }
    if ($gnuFlags.Help) { $Help = $true }
    if ($gnuFlags.Version) { $Version = $true }
}

if ($Help) {
    Write-Host @"
Usage: millennium-upgrade.ps1 [-Channel stable|beta|main] [-Force] [-File PATH] [-Rollback ID|list] [-DryRun] [-Yes] [-Quiet] [-Version] [-Help]

Install official Millennium (stable, beta, or main) releases over system files.

Options:
  -Channel CHANNEL  Update channel: stable, beta, or main (default: stable)
  -Force            Force reinstall even if already up to date
  -File PATH        Install from a local archive instead of downloading
  -Rollback ID      Roll back to a previous backup (or pass "list" to list backups)
  -DryRun           Simulate operations without modifying files
  -Yes, -y          Skip confirmation when closing Steam
  -Quiet, -q        Suppress informational output
  -Version, -V      Show version information
  -Help, -h         Show this help message

GNU-style flags (--channel, --stable, --beta, --main, --force, --file, --rollback, --yes, --quiet) are also accepted.
"@
    exit 0
}

if ($Version) {
    Write-HelpersVersion -Name "millennium-upgrade"
    exit 0
}

if ($Yes) {
    $global:AssumeYes = $true
}

if ($Quiet) {
    $global:Quiet = $true
    $env:MILLENNIUM_QUIET = "1"
}

if ($DryRun) {
    $global:DryRun = $true
    Log-Warn "=== DRY RUN MODE: No changes will be made ==="
}

$SteamPath = Resolve-SteamPath
if (!$SteamPath) {
    Log-Error "Error: Steam path could not be resolved."
    exit 1
}

$MillenniumDir = Join-Path -Path $SteamPath -ChildPath "millennium"
$WsockDll = Join-Path -Path $SteamPath -ChildPath "wsock32.dll"
$BackupDir = Join-Path -Path $SteamPath -ChildPath "millennium_backups"

# Parse configuration (backup limit / age + default channel)
$BackupLimit = 5
$BackupMaxAgeDays = $null
$configDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
$configFile = Join-Path -Path $configDir -ChildPath "config.json"
if (Test-Path -Path $configFile) {
    try {
        $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
        if ($config -and $config.backup_limit) {
            $BackupLimit = [int]$config.backup_limit
        }
        if ($config -and $null -ne $config.backup_max_age_days -and "$($config.backup_max_age_days)" -ne "") {
            $BackupMaxAgeDays = [int]$config.backup_max_age_days
        }
        if ($config -and $config.update_channel -and -not $channelExplicit) {
            $Channel = $config.update_channel
        }
    } catch {}
}

if ($Channel -ne "stable" -and $Channel -ne "beta" -and $Channel -ne "main") {
    Log-Error "Error: Invalid channel '$Channel'. Must be 'stable', 'beta', or 'main'."
    exit 1
}

# --- Rollback logic ---
if ($Rollback) {
    if ($Rollback -eq "list") {
        Log-Info "Available backups for rollback:"
        if (Test-Path -Path $BackupDir) {
            $backups = Get-ChildItem -Path $BackupDir -Directory | Sort-Object CreationTime -Descending
            if ($backups.Count -eq 0) {
                Write-Host "  No backups found."
            } else {
                foreach ($b in $backups) {
                    Write-Host "  - $($b.Name) (Created: $($b.CreationTime))"
                }
            }
        } else {
            Write-Host "  No backups directory exists."
        }
        Write-Host ""
        Write-Host "Apply one with: millennium upgrade -Rollback <id>"
        exit 0
    }

    # Perform actual rollback
    $targetBackup = Join-Path -Path $BackupDir -ChildPath $Rollback
    if (!(Test-Path -Path $targetBackup)) {
        Log-Error "Error: Backup '$Rollback' not found."
        exit 1
    }

    if (Is-GameRunning) {
        Log-Error "Error: A Steam game is currently running. Rollback aborted."
        Write-Host "Close the running game, then re-run. Use -Yes to skip the Steam close prompt."
        exit 1
    }

    # Gracefully close Steam
    $steamRunning = $null -ne (Get-Process -Name "steam" -ErrorAction SilentlyContinue)
    if ($steamRunning) {
        Capture-SteamEnv
        if (-not (Confirm-CloseSteam)) {
            exit 1
        }
    }

    Log-Info "Rolling back Millennium installation to $Rollback..."
    Execute-Cmd -ScriptBlock {
        # Delete current millennium folder and wsock32.dll
        if (Test-Path -Path $MillenniumDir) {
            Remove-Item -Path $MillenniumDir -Recurse -Force
        }
        if (Test-Path -Path $WsockDll) {
            Remove-Item -Path $WsockDll -Force
        }

        # Restore from backup
        Copy-Item -Path (Join-Path -Path $targetBackup -ChildPath "millennium") -Destination $MillenniumDir -Recurse -Force
        Copy-Item -Path (Join-Path -Path $targetBackup -ChildPath "wsock32.dll") -Destination $WsockDll -Force

        # Remove backup directory after successful rollback
        Remove-Item -Path $targetBackup -Recurse -Force
    } -Description "Rollback using backup $targetBackup"

    Log-Info "Rollback completed successfully."
    if ($steamRunning) {
        Relaunch-Steam
        Write-Host -ForegroundColor Green "Steam relaunched."
    }
    exit 0
}

# --- Version Tag Resolution ---
$latestVer = ""
$githubToken = $null
if ($File) {
    if (!(Test-Path -Path $File)) {
        Log-Error "Error: Local archive file '$File' not found."
        exit 1
    }
    $latestVer = "local"
} else {
    # Resolve version from GitHub
    $owner = "SteamClientHomebrew"
    $repo = "Millennium"
    $headers = @{}
    $githubToken = $env:GITHUB_TOKEN
    if (Test-Path -Path $configFile) {
        try {
            $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            if ($config -and $config.github_token) {
                $githubToken = $config.github_token
            }
        } catch {}
    }

    if ($githubToken) {
        $headers["Authorization"] = "token $githubToken"
    }

    Log-Info "Resolving latest version on the '$Channel' channel..."

    try {
        if ($Channel -eq "stable") {
            # Query latest stable release
            $url = "https://api.github.com/repos/$owner/$repo/releases/latest"
            $release = Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
            $latestVer = $release.tag_name.TrimStart('v')
        } elseif ($Channel -eq "main") {
            # Tip-of-dev: newest non-beta prerelease, else any prerelease
            $url = "https://api.github.com/repos/$owner/$repo/releases"
            $releases = Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
            foreach ($r in $releases) {
                if ($r.prerelease -and ($r.tag_name -notlike "*beta*")) {
                    $latestVer = $r.tag_name.TrimStart('v')
                    break
                }
            }
            if (!$latestVer) {
                foreach ($r in $releases) {
                    if ($r.prerelease) {
                        $latestVer = $r.tag_name.TrimStart('v')
                        break
                    }
                }
            }
            if (!$latestVer -and $releases.Count -gt 0) {
                $latestVer = $releases[0].tag_name.TrimStart('v')
            }
        } else {
            # Beta: newest prerelease / beta release
            $url = "https://api.github.com/repos/$owner/$repo/releases"
            $releases = Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
            foreach ($r in $releases) {
                if ($r.prerelease -or ($r.tag_name -like "*beta*" -or $r.tag_name -like "*alpha*")) {
                    $latestVer = $r.tag_name.TrimStart('v')
                    break
                }
            }
            if (!$latestVer -and $releases.Count -gt 0) {
                $latestVer = $releases[0].tag_name.TrimStart('v')
            }
        }
    } catch {
        Log-Error "Error: Could not retrieve release details from GitHub API: $_"
        Log-Error "If you are rate-limited, set a PAT: millennium schedule setup"
        Log-Error "  or: millennium-schedule config set github_token <token>"
        exit 1
    }
}

if (!$latestVer) {
    Log-Error "Error: Could not resolve a valid version tag."
    Log-Error "If you are rate-limited, set a PAT: millennium schedule setup"
    Log-Error "  or: millennium-schedule config set github_token <token>"
    exit 1
}

# Check currently installed version
$installedVerFile = Join-Path -Path $MillenniumDir -ChildPath "version.txt"
if (!$Force -and (Test-Path -Path $installedVerFile)) {
    $installedVer = (Get-Content -Path $installedVerFile -Raw).Trim()
    if ($installedVer -eq $latestVer) {
        Log-Info "Millennium is already up to date (v$latestVer). Use -Force to reinstall."
        exit 0
    }
}

# --- Download Archive ---
$tempDir = [System.IO.Path]::GetTempPath()
$archiveName = "millennium-v$latestVer-windows-x86_64.zip"
$localArchive = Join-Path -Path $tempDir -ChildPath $archiveName
$url = "https://github.com/SteamClientHomebrew/Millennium/releases/download/v$latestVer/$archiveName"
$shaUrl = "https://github.com/SteamClientHomebrew/Millennium/releases/download/v$latestVer/millennium-v$latestVer-windows-x86_64.sha256"
$expectedSha = $null

if (!$File) {
    Log-Info "Fetching SHA256 checksum for Millennium v$latestVer..."
    try {
        $shaHeaders = @{}
        if ($githubToken) {
            $shaHeaders["Authorization"] = "token $githubToken"
        }
        if ($shaHeaders.Count -gt 0) {
            $shaResp = Invoke-WebRequest -Uri $shaUrl -Headers $shaHeaders -UseBasicParsing -ErrorAction Stop
        } else {
            $shaResp = Invoke-WebRequest -Uri $shaUrl -UseBasicParsing -ErrorAction Stop
        }
        $expectedSha = (($shaResp.Content -as [string]).Trim() -split '\s+')[0]
    } catch {
        Log-Error "Error: Could not retrieve the SHA256 checksum for v$latestVer."
        Log-Error $_.Exception.Message
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($expectedSha) -or $expectedSha -notmatch '^[0-9a-fA-F]{64}$') {
        Log-Error "Error: Could not retrieve the SHA256 checksum for v$latestVer."
        exit 1
    }

    if ($global:DryRun) {
        Log-Warn "[DRY RUN] Would download: $url"
        Log-Warn "[DRY RUN] Expected SHA256: $expectedSha"
    } else {
        Log-Info "Downloading Millennium v$latestVer archive..."
        $dlSuccess = Download-File -Url $url -Dest $localArchive -Msg "Fetching Millennium client archive" -GithubToken $githubToken
        if (!$dlSuccess) {
            Write-UpgradeFailureTips -Detail "Failed to download Millennium package."
            exit 1
        }

        $actualSha = (Get-FileHash -Path $localArchive -Algorithm SHA256).Hash
        if ($actualSha.ToLowerInvariant() -ne $expectedSha.ToLowerInvariant()) {
            Log-Error "Error: SHA256 mismatch for downloaded Millennium archive."
            Log-Error "Expected: $expectedSha"
            Log-Error "Actual:   $actualSha"
            Remove-Item -Path $localArchive -Force -ErrorAction SilentlyContinue
            exit 1
        }
        Log-Info "SHA256 checksum verified."
    }
} else {
    $localArchive = $File
}

if (Is-GameRunning) {
    Log-Error "Error: A Steam game is currently running. Close all games before upgrading."
    Write-Host "Close the running game, then re-run. Use -Yes to skip the Steam close prompt."
    exit 1
}

$steamRunning = $null -ne (Get-Process -Name "steam" -ErrorAction SilentlyContinue)
if ($steamRunning) {
    Capture-SteamEnv
    if (-not (Confirm-CloseSteam)) {
        exit 1
    }
}

# --- Backup current files ---
if ((Test-Path -Path $MillenniumDir) -or (Test-Path -Path $WsockDll)) {
    Log-Info "Creating backup of current Millennium installation..."
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    # Resolve current version for naming
    $oldVer = "unknown"
    if (Test-Path -Path $installedVerFile) {
        $oldVer = (Get-Content -Path $installedVerFile -Raw).Trim()
    }
    $currBackupDir = Join-Path -Path $BackupDir -ChildPath "${oldVer}_${timestamp}"

    Execute-Cmd -ScriptBlock {
        New-Item -ItemType Directory -Force -Path $currBackupDir | Out-Null
        if (Test-Path -Path $MillenniumDir) {
            Copy-Item -Path $MillenniumDir -Destination (Join-Path -Path $currBackupDir -ChildPath "millennium") -Recurse -Force
        }
        if (Test-Path -Path $WsockDll) {
            Copy-Item -Path $WsockDll -Destination (Join-Path -Path $currBackupDir -ChildPath "wsock32.dll") -Force
        }
    } -Description "Backup current version to $currBackupDir"

    # Prune older backups (age first, then count — matches Unix prune_backups)
    if (Test-Path -Path $BackupDir) {
        if ($null -ne $BackupMaxAgeDays -and $BackupMaxAgeDays -ge 0) {
            $cutoff = (Get-Date).AddDays(-1 * $BackupMaxAgeDays)
            $aged = @(Get-ChildItem -Path $BackupDir -Directory | Where-Object { $_.CreationTime -lt $cutoff })
            foreach ($old in $aged) {
                Log-Info "Pruning aged backup: $($old.Name) (older than $BackupMaxAgeDays days)"
                Execute-Cmd -ScriptBlock {
                    Remove-Item -Path $old.FullName -Recurse -Force
                } -Description "Remove aged backup $($old.Name)"
            }
        }
        $backups = @(Get-ChildItem -Path $BackupDir -Directory | Sort-Object CreationTime)
        while ($backups.Count -ge $BackupLimit) {
            $oldest = $backups[0]
            Log-Info "Pruning oldest backup: $($oldest.Name)"
            Execute-Cmd -ScriptBlock {
                Remove-Item -Path $oldest.FullName -Recurse -Force
            } -Description "Remove oldest backup $oldest"
            $backups = @(Get-ChildItem -Path $BackupDir -Directory | Sort-Object CreationTime)
        }
    }
}

# --- Install Binaries ---
Log-Info "Extracting Millennium v$latestVer to Steam folder..."
Execute-Cmd -ScriptBlock {
    # Remove old millennium directory content
    if (Test-Path -Path $MillenniumDir) {
        Remove-Item -Path $MillenniumDir -Recurse -Force
    }

    # Extract new zip
    # Expand-Archive is native to PowerShell 5+
    Expand-Archive -Path $localArchive -DestinationPath $SteamPath -Force

    # Save version info
    $latestVer | Set-Content -Path $installedVerFile -Force
} -Description "Extract $localArchive to $SteamPath"

# Cleanup downloaded file if not using a custom local file input
if (!$File -and !$global:DryRun -and (Test-Path -Path $localArchive)) {
    Remove-Item -Path $localArchive -Force
}

if ($global:DryRun) {
    Write-Host -ForegroundColor Green "Dry run completed successfully!"
} else {
    Write-Host -ForegroundColor Green "Done. Installed Millennium v$latestVer ($Channel channel)."
    if ($steamRunning) {
        Write-Host "Steam will be relaunched."
    }
}

if ($steamRunning) {
    Relaunch-Steam
    if (-not $global:DryRun) {
        Write-Host -ForegroundColor Green "Steam relaunched."
    }
}
exit 0
