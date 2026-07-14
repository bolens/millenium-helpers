# Millennium Theme Manager for Windows
param(
    [string]$Command = $null,
    [string]$Theme = $null,
    [switch]$All = $false,
    [switch]$Json = $false,
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

function Show-Help {
    Write-Output @"
Usage: millennium-theme COMMAND [ARGUMENTS] [OPTIONS]

Commands:
  list                  List all installed Millennium themes
  install [owner/repo]  Install a theme from a GitHub repository
  update [theme-name]   Update an installed theme to its latest commit
  remove [theme-name]   Uninstall/remove an installed theme

Options:
  -Json                 Output list command results in structured JSON format
  -d, -DryRun           Perform a dry-run (simulates operations without modifying files)
  -y, -Yes              Skip confirmation when removing a theme
  -q, -Quiet            Suppress informational output
  -V, -Version          Show version information
  -h, -Help             Show this help message

GNU-style flags (--json, --dry-run, --yes, --quiet) are also accepted.

Examples:
  millennium theme install SteamClientHomebrew/millennium-steam-skin
  millennium theme list
"@
}

# Resolve command positional parameters / GNU-style flags from unbound args
if ($args.Count -gt 0) {
    $gnuFlags = @{
        Json = [bool]$Json
        DryRun = [bool]$DryRun
        Yes = [bool]$Yes
        Quiet = [bool]$Quiet
        Help = [bool]$Help
        Version = [bool]$Version
        All = [bool]$All
    }
    $remaining = Apply-GnuStyleArgs -InputArgs ([string[]]$args) -Target $gnuFlags
    if ($gnuFlags.Json) { $Json = $true }
    if ($gnuFlags.DryRun) { $DryRun = $true }
    if ($gnuFlags.Yes) { $Yes = $true }
    if ($gnuFlags.Quiet) { $Quiet = $true; $global:Quiet = $true; $env:MILLENNIUM_QUIET = "1" }
    if ($gnuFlags.Help) { $Help = $true }
    if ($gnuFlags.Version) { $Version = $true }
    if ($gnuFlags.All) { $All = $true }
    if ($remaining.Count -gt 0) {
        if (!$Command) { $Command = $remaining[0] }
        if ($remaining.Count -gt 1 -and !$Theme) {
            if ($remaining[1] -ne "-a" -and $remaining[1] -ne "--all") {
                $Theme = $remaining[1]
            } else {
                $All = $true
            }
        }
    }
}

if ($Quiet) {
    $global:Quiet = $true
    $env:MILLENNIUM_QUIET = "1"
}

if ($Help -or $Command -eq "help" -or $Command -eq "--help" -or $Command -eq "-h") {
    Show-Help
    exit 0
}
if ($Version -or $Command -eq "version" -or $Command -eq "--version" -or $Command -eq "-V") {
    Write-HelpersVersion -Name "millennium-theme"
    exit 0
}

$knownCommands = @("list", "install", "update", "remove")
if (-not $Command) {
    Show-Help
    exit 1
}
if ($knownCommands -notcontains $Command) {
    Log-Error "Unknown command: $Command"
    $suggestion = Get-ClosestToken -InputToken $Command -Candidates $knownCommands
    if ($suggestion) {
        Write-Host "Did you mean '$suggestion'?"
    }
    Write-Host "Try 'millennium-theme -Help' for usage."
    exit 1
}

if ($Yes) {
    $global:AssumeYes = $true
}

if ($DryRun) {
    $global:DryRun = $true
}

function Resolve-MillenniumGo {
    $candidates = @(
        (Join-Path -Path $ScriptDir -ChildPath 'millennium.exe'),
        (Join-Path -Path $ScriptDir -ChildPath '..\..\bin\millennium.exe'),
        (Join-Path -Path $ScriptDir -ChildPath '..\millennium.exe')
    )
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            return (Resolve-Path -LiteralPath $cand).Path
        }
    }
    foreach ($name in @('millennium.exe', 'millennium')) {
        $cmd = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Invoke-ThemeListViaGo {
    $goBin = Resolve-MillenniumGo
    if (-not $goBin) {
        Write-Error "theme list requires the Go millennium dispatcher (not found). Install millennium-helpers or run 'make build'."
        exit 1
    }
    $goArgs = [System.Collections.Generic.List[string]]::new()
    [void]$goArgs.Add('theme')
    [void]$goArgs.Add('list')
    if ($Json) { [void]$goArgs.Add('--json') }
    if ($Quiet) { [void]$goArgs.Add('--quiet') }
    $prevLegacy = $env:MILLENNIUM_LEGACY
    $env:MILLENNIUM_LEGACY = '0'
    try {
        & $goBin @($goArgs.ToArray())
        exit $LASTEXITCODE
    } finally {
        if ($null -eq $prevLegacy) {
            Remove-Item Env:MILLENNIUM_LEGACY -ErrorAction SilentlyContinue
        } else {
            $env:MILLENNIUM_LEGACY = $prevLegacy
        }
    }
}

# Phase 6e: list is Go-only (thin-wrap) — before Steam resolve / ThemeOps.
if ($Command -eq "list") {
    Invoke-ThemeListViaGo
}

$SteamPath = Resolve-SteamPath
if (!$SteamPath) {
    Log-Error "Error: Steam installation path could not be resolved."
    exit 1
}

$SkinsDir = Join-Path -Path $SteamPath -ChildPath "steamui\skins"
$configDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
$configFile = Join-Path -Path $configDir -ChildPath "config.json"

# Feature modules (dot-sourced by this entrypoint — no thin aggregator)
. (Join-Path -Path $ScriptDir -ChildPath 'lib\ThemeOps.ps1')

# --- Command Handler ---

if ($Command -eq "install") {
    if (!$Theme) {
        Log-Error "Error: Install command requires an owner/repo argument."
        exit 1
    }

    # Normalize backslashes to forward slashes for repo format validation
    $Theme = $Theme -replace '\\', '/'

    if ($Theme -notlike "*/*" -or $Theme -like "*/*/*") {
        Log-Error "Error: Theme target must be in the format 'owner/repo'."
        exit 1
    }

    $parts = $Theme -split "/"
    $owner = $parts[0]
    $repo = $parts[1]

    Sanitize-ThemeComponent -Val $owner -Label "owner"
    Sanitize-ThemeComponent -Val $repo -Label "repo"

    $targetDir = Resolve-ThemeDir -Component $repo
    if (Test-Path -Path $targetDir) {
        Log-Error "Error: Theme directory '$repo' already exists."
        exit 1
    }

    # Resolve latest commit using GitHub API
    $githubToken = $env:GITHUB_TOKEN
    $headers = @{}
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

    Log-Info "Resolving latest commit for $owner/$repo..."
    $commit = ""
    try {
        $apiRes = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/commits" -Headers $headers -UseBasicParsing -ErrorAction Stop
        if ($apiRes -and $apiRes.Count -gt 0) {
            $commit = $apiRes[0].sha
        }
    } catch {
        Log-Error "Error: Could not retrieve repository info from GitHub: $_"
        exit 1
    }

    if (!$commit) {
        Log-Error "Error: Commit SHA resolution failed."
        exit 1
    }

    # Download theme package zip
    $tempDir = [System.IO.Path]::GetTempPath()
    $archiveName = "theme_${repo}_$commit.zip"
    $localZip = Join-Path -Path $tempDir -ChildPath $archiveName
    $zipUrl = "https://github.com/$owner/$repo/archive/$commit.zip"

    $success = Download-File -Url $zipUrl -Dest $localZip -Msg "Downloading theme package" -GithubToken $githubToken
    if (!$success) {
        Log-Error "Error: Theme download failed."
        exit 1
    }

    Log-Info "Installing theme '$repo'..."
    Execute-Cmd -ScriptBlock {
        # Create skins directory if missing
        if (!(Test-Path -Path $SkinsDir)) {
            New-Item -ItemType Directory -Force -Path $SkinsDir | Out-Null
        }

        # Extract zip to temp location
        $tempExtract = Join-Path -Path $tempDir -ChildPath "extract_${repo}_$commit"
        if (Test-Path -Path $tempExtract) {
            Remove-Item -Path $tempExtract -Recurse -Force
        }
        Expand-SafeArchive -Path $localZip -DestinationPath $tempExtract

        # Move extracted folder (which has GitHub zip-naming: repo-commit)
        $extractedDir = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
        if ($extractedDir) {
            Move-Item -Path $extractedDir.FullName -Destination $targetDir -Force
        }

        # Cleanup extract directory
        Remove-Item -Path $tempExtract -Recurse -Force

        # Save metadata.json
        $metaObj = @{
            "owner" = $owner;
            "repo" = $repo;
            "commit" = $commit;
        }
        $metaObj | ConvertTo-Json | Set-Content -Path (Join-Path -Path $targetDir -ChildPath "metadata.json") -Force
    } -Description "Extract and install theme $repo to skins folder"

    if (!$global:DryRun -and (Test-Path -Path $localZip)) {
        Remove-Item -Path $localZip -Force
    }

    Log-Info "Theme '$repo' successfully installed."
    Write-Host "Next: enable it in Steam -> Millennium -> Themes (or Settings)."
    Write-Host "Tip: millennium theme list shows installed themes; the active one is marked."
    exit 0
}

if ($Command -eq "remove") {
    if (!$Theme) {
        Log-Error "Error: Remove command requires a theme name argument."
        exit 1
    }

    Sanitize-ThemeComponent -Val $Theme -Label "theme name"
    $targetDir = Resolve-ThemeDir -Component $Theme

    if (!(Test-Path -Path $targetDir)) {
        Log-Error "Error: Theme '$Theme' is not installed."
        exit 1
    }

    $activeTheme = Get-ActiveThemeName
    if ($Theme -eq $activeTheme) {
        Log-Warn "Warning: '$Theme' is currently the active Millennium theme."
    }

    $assumeYes = $Yes -or $global:AssumeYes -or $env:TEST_SUITE_RUN -or $env:PSTESTS
    $interactive = $false
    try {
        $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    } catch {
        $interactive = $false
    }

    if (-not $assumeYes -and $interactive) {
        $reply = Read-Host "Remove theme '$Theme'? [y/N]"
        if ($reply -notmatch '^[Yy]([Ee][Ss])?$') {
            Log-Info "Aborted."
            exit 0
        }
    }

    Log-Info "Removing theme '$Theme'..."
    Execute-Cmd -ScriptBlock {
        Remove-Item -Path $targetDir -Recurse -Force
    } -Description "Remove-Item -Path $targetDir -Recurse -Force"

    Log-Info "Theme '$Theme' removed successfully."
    exit 0
}

if ($Command -eq "update") {
    $themesToUpdate = @()
    if ($All -or !$Theme) {
        # Multi-update mode
        if (Test-Path -Path $SkinsDir) {
            $themesToUpdate = Get-ChildItem -Path $SkinsDir -Directory
        }
    } else {
        Sanitize-ThemeComponent -Val $Theme -Label "theme name"
        $targetDir = Resolve-ThemeDir -Component $Theme
        if (!(Test-Path -Path $targetDir)) {
            Log-Error "Error: Theme '$Theme' is not installed."
            exit 1
        }
        $themesToUpdate = @(Get-Item -Path $targetDir)
    }

    if ($themesToUpdate.Count -eq 0) {
        Log-Info "No installed themes detected for update."
        Write-Host "Install one with: millennium theme install SteamClientHomebrew/millennium-steam-skin"
        exit 0
    }

    foreach ($t in $themesToUpdate) {
        $meta = Get-ThemeMetadata -ThemeDir $t.FullName
        if ($null -eq $meta) {
            Log-Warn "Skipping local/untracked theme '$($t.Name)'."
            continue
        }

        $owner = $meta.owner
        $repo = $meta.repo
        $currentCommit = $meta.commit

        Log-Info "Checking updates for theme '$($t.Name)' ($owner/$repo)..."

        # Resolve latest commit using GitHub API
        $githubToken = $env:GITHUB_TOKEN
        $headers = @{}
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

        $commit = ""
        try {
            $apiRes = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/commits" -Headers $headers -UseBasicParsing -ErrorAction Stop
            if ($apiRes -and $apiRes.Count -gt 0) {
                $commit = $apiRes[0].sha
            }
        } catch {
            Log-Error "Error: Could not retrieve repository info from GitHub: $_"
            continue
        }

        if ($currentCommit -eq $commit) {
            Log-Info "Theme '$($t.Name)' is already up to date."
            continue
        }

        # Update by removing and re-installing
        Log-Info "Updating theme '$($t.Name)' to commit $commit..."
        $tempDir = [System.IO.Path]::GetTempPath()
        $archiveName = "theme_${repo}_$commit.zip"
        $localZip = Join-Path -Path $tempDir -ChildPath $archiveName
        $zipUrl = "https://github.com/$owner/$repo/archive/$commit.zip"

        $success = Download-File -Url $zipUrl -Dest $localZip -Msg "Downloading theme package" -GithubToken $githubToken
        if (!$success) {
            Log-Error "Error: Theme update download failed."
            continue
        }

        $targetDir = $t.FullName
        Execute-Cmd -ScriptBlock {
            Remove-Item -Path $targetDir -Recurse -Force

            # Extract zip to temp location
            $tempExtract = Join-Path -Path $tempDir -ChildPath "extract_${repo}_$commit"
            if (Test-Path -Path $tempExtract) {
                Remove-Item -Path $tempExtract -Recurse -Force
            }
            Expand-SafeArchive -Path $localZip -DestinationPath $tempExtract

            # Move extracted folder (which has GitHub zip-naming: repo-commit)
            $extractedDir = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
            if ($extractedDir) {
                Move-Item -Path $extractedDir.FullName -Destination $targetDir -Force
            }

            # Cleanup extract directory
            Remove-Item -Path $tempExtract -Recurse -Force

            # Save metadata.json
            $metaObj = @{
                "owner" = $owner;
                "repo" = $repo;
                "commit" = $commit;
            }
            $metaObj | ConvertTo-Json | Set-Content -Path (Join-Path -Path $targetDir -ChildPath "metadata.json") -Force
        } -Description "Upgrade theme $($t.Name) by replacing content"

        if (!$global:DryRun -and (Test-Path -Path $localZip)) {
            Remove-Item -Path $localZip -Force
        }

        Log-Info "Theme '$($t.Name)' successfully updated."
    }
    exit 0
}
