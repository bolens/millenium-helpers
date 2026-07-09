# Millennium Theme Manager for Windows
param(
    [string]$Command = $null,
    [string]$Theme = $null,
    [switch]$All = $false,
    [switch]$Json = $false,
    [switch]$DryRun = $false
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

# Resolve command positional parameters
if ($args.Count -gt 0) {
    if (!$Command) { $Command = $args[0] }
    if ($args.Count -gt 1 -and !$Theme) {
        if ($args[1] -ne "-a" -and $args[1] -ne "--all") {
            $Theme = $args[1]
        } else {
            $All = $true
        }
    }
}

if ($DryRun) {
    $global:DryRun = $true
}

$SteamPath = Resolve-SteamPath
if (!$SteamPath) {
    Log-Error "Error: Steam installation path could not be resolved."
    exit 1
}

$SkinsDir = Join-Path -Path $SteamPath -ChildPath "steamui\skins"
$configDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
$configFile = Join-Path -Path $configDir -ChildPath "config.json"

function Sanitize-ThemeComponent {
    param(
        [string]$Val,
        [string]$Label
    )
    if (!$Val -or $Val -eq "." -or $Val -eq ".." -or $Val.Contains('/') -or $Val.Contains('\') -or $Val.Contains('*')) {
        Log-Error "Error: Invalid $Label '$Val'."
        exit 1
    }
}

function Resolve-ThemeDir {
    param([string]$Component)
    $candidate = Join-Path -Path $SkinsDir -ChildPath $Component
    
    # Path traversal verification
    $resolvedCandidate = [System.IO.Path]::GetFullPath($candidate)
    $resolvedSkins = [System.IO.Path]::GetFullPath($SkinsDir)
    
    if (!$resolvedCandidate.StartsWith($resolvedSkins)) {
        Log-Error "Error: Resolved theme path '$resolvedCandidate' escapes the skins directory."
        exit 1
    }
    return $resolvedCandidate
}

function Get-ThemeMetadata {
    param([string]$ThemeDir)
    $metaFile = Join-Path -Path $ThemeDir -ChildPath "metadata.json"
    if (Test-Path -Path $metaFile) {
        try {
            $meta = Get-Content -Path $metaFile -Raw | ConvertFrom-Json
            if ($meta -and $meta.owner -and $meta.repo) {
                return $meta
            }
        } catch {}
    }
    return $null
}

# --- Command Handler ---

if ($Command -eq "list") {
    if (!(Test-Path -Path $SkinsDir)) {
        if ($Json) {
            Write-Output "[]"
        } else {
            Log-Info "No themes directory found. Install a theme first."
        }
        exit 0
    }

    $themes = Get-ChildItem -Path $SkinsDir -Directory
    $list = @()

    foreach ($t in $themes) {
        $meta = Get-ThemeMetadata -ThemeDir $t.FullName
        if ($null -ne $meta) {
            $list += [ordered]@{
                "name" = $t.Name;
                "type" = "github";
                "owner" = $meta.owner;
                "repo" = $meta.repo;
                "commit" = $meta.commit;
            }
        } else {
            $list += [ordered]@{
                "name" = $t.Name;
                "type" = "local";
                "owner" = "";
                "repo" = "";
                "commit" = "";
            }
        }
    }

    if ($Json) {
        $list | ConvertTo-Json
    } else {
        Write-Host "=== Installed Millennium Themes ==="
        foreach ($item in $list) {
            if ($item.type -eq "github") {
                Write-Host "  - $($item.name) [GitHub: $($item.owner)/$($item.repo) @ $($item.commit.Substring(0,7))]"
            } else {
                Write-Host "  - $($item.name) [Local Theme (untracked)]"
            }
        }
    }
    exit 0
}

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
        Expand-Archive -Path $localZip -DestinationPath $tempExtract -Force
        
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
            Expand-Archive -Path $localZip -DestinationPath $tempExtract -Force
            
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

show_help
exit 1
