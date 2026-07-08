# PowerShell script to upgrade or reinstall the Millennium client on Windows
param(
    [string]$Channel = "stable",
    [switch]$Force = $false,
    [string]$File = $null,
    [string]$Rollback = $null,
    [switch]$DryRun = $false
)
set-strictmode -version Latest

# Source shared helpers
$ScriptDir = Split-Path -Parent $MyInvocation.ScriptName
$CommonPs1 = Join-Path -Path $ScriptDir -ChildPath "common.ps1"
if (Test-Path -Path $CommonPs1) {
    . $CommonPs1
} else {
    Write-Error "Shared helper library not found at $CommonPs1"
    exit 1
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

# Parse configuration (backup limit)
$BackupLimit = 5
$userHome = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
if (!$userHome) { $userHome = $env:USERPROFILE }
$configDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
$configFile = Join-Path -Path $configDir -ChildPath "config.json"
if (Test-Path -Path $configFile) {
    try {
        $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
        if ($config -and $config.backup_limit) {
            $BackupLimit = [int]$config.backup_limit
        }
        if ($config -and $config.update_channel -and ($MyInvocation.BoundParameters.ContainsKey('Channel') -eq $false)) {
            $Channel = $config.update_channel
        }
    } catch {}
}

if ($Channel -ne "stable" -and $Channel -ne "beta") {
    Log-Error "Error: Invalid channel '$Channel'. Must be 'stable' or 'beta'."
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
        exit 1
    }

    # Gracefully close Steam
    $steamRunning = $null -ne (Get-Process -Name "steam" -ErrorAction SilentlyContinue)
    if ($steamRunning) {
        Capture-SteamEnv
        Close-SteamGracefully
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
    }
    exit 0
}

# --- Version Tag Resolution ---
$latestVer = ""
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
        } else {
            # Query releases and find the newest prerelease / beta release
            $url = "https://api.github.com/repos/$owner/$repo/releases"
            $releases = Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
            foreach ($r in $releases) {
                if ($r.prerelease -or ($r.tag_name -like "*beta*" -or $r.tag_name -like "*alpha*")) {
                    $latestVer = $r.tag_name.TrimStart('v')
                    break
                }
            }
            if (!$latestVer -and $releases.Count -gt 0) {
                # Fall back to latest release if no prerelease exists
                $latestVer = $releases[0].tag_name.TrimStart('v')
            }
        }
    } catch {
        Log-Error "Error: Could not retrieve release details from GitHub API: $_"
        exit 1
    }
}

if (!$latestVer) {
    Log-Error "Error: Could not resolve a valid version tag."
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

if (!$File) {
    Log-Info "Downloading Millennium v$latestVer archive..."
    $dlSuccess = Download-File -Url $url -Dest $localArchive -Msg "Fetching Millennium client archive" -GithubToken $githubToken
    if (!$dlSuccess) {
        Log-Error "Error: Failed to download Millennium package."
        exit 1
    }
} else {
    $localArchive = $File
}

if (Is-GameRunning) {
    Log-Error "Error: A Steam game is currently running. Close all games before upgrading."
    exit 1
}

$steamRunning = $null -ne (Get-Process -Name "steam" -ErrorAction SilentlyContinue)
if ($steamRunning) {
    Capture-SteamEnv
    Close-SteamGracefully
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

    # Prune older backups
    if (Test-Path -Path $BackupDir) {
        $backups = Get-ChildItem -Path $BackupDir -Directory | Sort-Object CreationTime
        while ($backups.Count -ge $BackupLimit) {
            $oldest = $backups[0]
            Log-Info "Pruning oldest backup: $($oldest.Name)"
            Execute-Cmd -ScriptBlock {
                Remove-Item -Path $oldest.FullName -Recurse -Force
            } -Description "Remove oldest backup $oldest"
            $backups = Get-ChildItem -Path $BackupDir -Directory | Sort-Object CreationTime
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

Log-Info "Millennium v$latestVer installed successfully."

if ($steamRunning) {
    Relaunch-Steam
}
exit 0
