# ThemeOps.ps1 - Theme helpers for millennium-theme.ps1

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

function Get-ActiveThemeName {
    # Millennium has used several config locations across versions/install layouts.
    $candidates = @()
    if ($env:APPDATA) {
        $candidates += (Join-Path -Path $env:APPDATA -ChildPath "millennium\config.json")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium\config.json")
    }
    if ($SteamPath) {
        $candidates += (Join-Path -Path $SteamPath -ChildPath "millennium\config.json")
        $candidates += (Join-Path -Path $SteamPath -ChildPath "ext\config.json")
    }
    foreach ($cand in $candidates) {
        if (!(Test-Path -Path $cand -PathType Leaf)) { continue }
        try {
            $data = Get-Content -Path $cand -Raw | ConvertFrom-Json
            if ($data -and $data.themes -and $data.themes.activeTheme) {
                return [string]$data.themes.activeTheme
            }
        } catch {}
    }
    return "Steam"
}
