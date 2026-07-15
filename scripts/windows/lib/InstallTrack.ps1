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

function Get-HelpersBinAssetName {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [ValidateSet('windows', 'linux')]
        [string]$Platform = 'windows'
    )
    $ver = $Version.TrimStart('v')
    if ($Platform -eq 'windows') {
        return "millennium-helpers-v$ver-windows-amd64.zip"
    }
    $arch = 'amd64'
    try {
        $m = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
        if ($m -match 'arm') { $arch = 'arm64' }
    } catch {
        # keep amd64
    }
    return "millennium-helpers-v$ver-linux-$arch.tar.gz"
}

function Get-LatestHelpersReleaseTag {
    param([string]$Repo = $script:HelpersGitHubRepo)
    $headers = @{
        'User-Agent' = 'millennium-helpers'
        'Accept'     = 'application/vnd.github+json'
    }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -UseBasicParsing
    if (-not $release.tag_name) { throw "Could not resolve latest release tag for $Repo" }
    return [string]$release.tag_name
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
            $latest = Get-LatestHelpersReleaseTag
            $ver = $latest.TrimStart('v')
            $asset = Get-HelpersBinAssetName -Version $ver -Platform $Platform
            $result.Ref = $latest
            $result.Version = $ver
            $result.Url = "https://github.com/$($script:HelpersGitHubRepo)/releases/download/$latest/$asset"
            $result.ShaUrl = "$($result.Url).sha256"
            $result.NeedsSha = $true
        }
        'tag' {
            if ([string]::IsNullOrWhiteSpace($Tag)) {
                throw "Tag is required for track=tag"
            }
            $norm = Normalize-HelpersTag -Tag $Tag
            $ver = $norm.TrimStart('v')
            $asset = Get-HelpersBinAssetName -Version $ver -Platform $Platform
            $result.Ref = $norm
            $result.Version = $ver
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
    # Use System.IO so tests that mock Get-Content/Set-Content cannot break meta I/O.
    $json = ($data | ConvertTo-Json -Depth 5) + "`n"
    [System.IO.File]::WriteAllText($path, $json)
}

function Read-HelpersInstallMeta {
    param([string]$InstallRoot = $(Join-Path $env:USERPROFILE '.millennium-helpers'))
    $path = Get-HelpersInstallMetaPath -InstallRoot $InstallRoot
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    try {
        $raw = [System.IO.File]::ReadAllText($path)
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
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
        try {
            $version = [System.IO.File]::ReadAllText($versionFile).Trim()
        } catch {
            $version = ''
        }
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
