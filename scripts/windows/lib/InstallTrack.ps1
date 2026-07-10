# Helpers install track resolution, install-meta.json, and legacy migrate.
# Tracks: release | main | tag | checkout

$script:HelpersGitHubRepo = if ($env:HELPERS_GITHUB_REPO) { $env:HELPERS_GITHUB_REPO } else { 'bolens/millenium-helpers' }
$script:HelpersInstallMetaName = 'install-meta.json'

function Get-HelpersInstallMetaPath {
    param([string]$InstallRoot = $(Join-Path $env:USERPROFILE '.millennium-helpers'))
    return (Join-Path $InstallRoot $script:HelpersInstallMetaName)
}

function Normalize-HelpersTag {
    param([Parameter(Mandatory = $true)][string]$Tag)
    $t = $Tag.Trim()
    if ($t.StartsWith('v')) { return $t }
    if ([string]::IsNullOrWhiteSpace($t)) { throw "Tag is empty" }
    return "v$t"
}

function Resolve-HelpersInstallTrack {
    param(
        [string]$Track = '',
        [string]$Tag = '',
        [ValidateSet('windows', 'linux')]
        [string]$Platform = 'windows'
    )

    if ([string]::IsNullOrWhiteSpace($Track)) {
        $Track = if ($env:MILLENNIUM_HELPERS_TRACK) { $env:MILLENNIUM_HELPERS_TRACK } else { 'release' }
    }
    if ([string]::IsNullOrWhiteSpace($Tag) -and $env:MILLENNIUM_HELPERS_TAG) {
        $Tag = $env:MILLENNIUM_HELPERS_TAG
    }
    $Track = $Track.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($Tag)) {
        $Track = 'tag'
    }

    $asset = if ($Platform -eq 'windows') {
        'millennium-helpers-windows.zip'
    } else {
        'millennium-helpers-linux.tar.gz'
    }

    $result = [ordered]@{
        Track            = $Track
        Ref              = ''
        Version          = ''
        Url              = ''
        ShaUrl           = ''
        NeedsSha         = $false
        IsSourceArchive  = $false
    }

    if ($env:MILLENNIUM_HELPERS_RELEASE_URL) {
        $result.Url = $env:MILLENNIUM_HELPERS_RELEASE_URL
        $result.ShaUrl = if ($env:MILLENNIUM_HELPERS_RELEASE_SHA_URL) {
            $env:MILLENNIUM_HELPERS_RELEASE_SHA_URL
        } else {
            "$($result.Url).sha256"
        }
        $result.NeedsSha = $true
        switch ($Track) {
            'tag' {
                $norm = Normalize-HelpersTag -Tag $Tag
                $result.Ref = $norm
                $result.Version = $norm.TrimStart('v')
            }
            'main' {
                $result.Ref = 'main'
                $result.IsSourceArchive = $true
                $result.NeedsSha = $false
            }
            default { $result.Ref = 'latest' }
        }
        return [pscustomobject]$result
    }

    switch ($Track) {
        'release' {
            $result.Ref = 'latest'
            $result.Url = "https://github.com/$($script:HelpersGitHubRepo)/releases/latest/download/$asset"
            $result.ShaUrl = "$($result.Url).sha256"
            $result.NeedsSha = $true
        }
        'tag' {
            if ([string]::IsNullOrWhiteSpace($Tag)) {
                throw "Tag is required for track=tag"
            }
            $norm = Normalize-HelpersTag -Tag $Tag
            $result.Ref = $norm
            $result.Version = $norm.TrimStart('v')
            $result.Url = "https://github.com/$($script:HelpersGitHubRepo)/releases/download/$norm/$asset"
            $result.ShaUrl = "$($result.Url).sha256"
            $result.NeedsSha = $true
        }
        'main' {
            $result.Ref = 'main'
            $result.IsSourceArchive = $true
            $result.NeedsSha = $false
            if ($Platform -eq 'windows') {
                $result.Url = "https://github.com/$($script:HelpersGitHubRepo)/archive/refs/heads/main.zip"
            } else {
                $result.Url = "https://github.com/$($script:HelpersGitHubRepo)/archive/refs/heads/main.tar.gz"
            }
        }
        'checkout' {
            $result.Ref = 'checkout'
        }
        default {
            throw "Invalid helpers track '$Track' (expected release|main|tag)"
        }
    }

    return [pscustomobject]$result
}

function Write-HelpersInstallMeta {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$Track,
        [string]$Ref = '',
        [string]$Version = '',
        [string]$SourceUrl = '',
        [string]$MigratedFrom = ''
    )
    if (!(Test-Path -LiteralPath $InstallRoot)) {
        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    }
    $path = Get-HelpersInstallMetaPath -InstallRoot $InstallRoot
    $data = [ordered]@{
        track          = $Track
        ref            = if ($Ref) { $Ref } else { $null }
        version        = if ($Version) { $Version } else { $null }
        source_url     = if ($SourceUrl) { $SourceUrl } else { $null }
        installed_at   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        migrated_from  = if ($MigratedFrom) { $MigratedFrom } else { $null }
    }
    ($data | ConvertTo-Json -Depth 5) + "`n" | Set-Content -Path $path -Encoding utf8
}

function Read-HelpersInstallMeta {
    param([string]$InstallRoot = $(Join-Path $env:USERPROFILE '.millennium-helpers'))
    $path = Get-HelpersInstallMetaPath -InstallRoot $InstallRoot
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Migrate-HelpersInstallMetaIfNeeded {
    param(
        [string]$InstallRoot = $(Join-Path $env:USERPROFILE '.millennium-helpers'),
        [string]$Method = 'manual',
        [string]$Checkout = ''
    )
    $path = Get-HelpersInstallMetaPath -InstallRoot $InstallRoot
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        return $false
    }

    $versionFile = Join-Path $InstallRoot 'bin\VERSION'
    if (!(Test-Path -LiteralPath $versionFile)) {
        $versionFile = Join-Path $InstallRoot 'VERSION'
    }
    $version = ''
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
    }

    $track = 'release'
    $ref = 'latest'
    switch -Regex ($Method) {
        'scoop-git|winget-git|^main$' {
            $track = 'main'; $ref = 'main'
        }
        '^checkout$' {
            $track = 'checkout'
            $ref = 'checkout'
        }
        default {
            $track = 'release'
            if ($version) { $ref = "v$version" } else { $ref = 'latest' }
        }
    }

    Write-HelpersInstallMeta -InstallRoot $InstallRoot -Track $track -Ref $ref -Version $version -MigratedFrom 'legacy'
    return $true
}

function Get-HelpersMainCommitSha {
    param([string]$Repo = $script:HelpersGitHubRepo)
    try {
        $headers = @{
            'User-Agent' = 'millennium-helpers'
            'Accept'     = 'application/vnd.github+json'
        }
        $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/commits/main" -Headers $headers
        return [string]$resp.sha
    } catch {
        return ''
    }
}
