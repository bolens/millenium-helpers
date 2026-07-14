# DiagRelease.ps1 - GitHub release tag fetch and release zip download/extraction
#
# Populates / manages:
#   $script:LatestReleaseTag     (also set by DiagInstall.ps1 to '')
#   $script:LatestReleaseVersion
#   $script:DiagReleaseExtract   path to extracted zip contents (or '')
#   $script:DiagReleaseWorkdir   temp workdir to clean up

$script:DiagReleaseExtract  = ''
$script:DiagReleaseWorkdir  = ''

function Get-LatestReleaseTag {
    $script:LatestReleaseTag     = ''
    $script:LatestReleaseVersion = ''

    $apiUrl = 'https://api.github.com/repos/bolens/millenium-helpers/releases/latest'
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        if ($response -and $response.tag_name) {
            $script:LatestReleaseTag     = $response.tag_name
            $script:LatestReleaseVersion = $response.tag_name -replace '^v', ''
        }
    } catch {
        # Offline or rate-limited; callers handle empty tag gracefully
    }
}

function Invoke-DiagReleaseCleanup {
    if ($script:DiagReleaseWorkdir -and (Test-Path -Path $script:DiagReleaseWorkdir)) {
        Remove-Item -Path $script:DiagReleaseWorkdir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:DiagReleaseWorkdir = ''
    $script:DiagReleaseExtract = ''
}

function Get-ReleaseZipExtract {
    # Test bypass: point at a pre-extracted directory
    if ($env:DIAG_TEST_RELEASE_EXTRACT) {
        $script:DiagReleaseExtract = $env:DIAG_TEST_RELEASE_EXTRACT
        return $true
    }

    # Re-use if already extracted
    if ($script:DiagReleaseExtract -and (Test-Path -Path $script:DiagReleaseExtract)) {
        return $true
    }

    Invoke-DiagReleaseCleanup

    $workdir = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath ("millennium-diag-release-" + [guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Force -Path $workdir | Out-Null
    $script:DiagReleaseWorkdir = $workdir

    $track = if ($script:HelpersTrack) { $script:HelpersTrack } else { 'release' }
    $zipPath = Join-Path -Path $workdir -ChildPath 'helpers-download.zip'
    $shaPath = Join-Path -Path $workdir -ChildPath 'helpers-download.zip.sha256'
    $extractDir = Join-Path -Path $workdir -ChildPath 'extract'
    $url = ''
    $needsSha = $true

    switch ($track) {
        'main' {
            $url = 'https://github.com/bolens/millenium-helpers/archive/refs/heads/main.zip'
            $needsSha = $false
        }
        'tag' {
            $tag = if ($script:HelpersTrackRef) { $script:HelpersTrackRef } else { $script:LatestReleaseTag }
            if (-not $tag) { Invoke-DiagReleaseCleanup; return $false }
            $url = "https://github.com/bolens/millenium-helpers/releases/download/$tag/millennium-helpers-windows.zip"
        }
        default {
            $tag = if ($script:LatestReleaseTag) { $script:LatestReleaseTag } else { '' }
            if (-not $tag) { Get-LatestReleaseTag; $tag = $script:LatestReleaseTag }
            if (-not $tag) { Invoke-DiagReleaseCleanup; return $false }
            $url = "https://github.com/bolens/millenium-helpers/releases/download/$tag/millennium-helpers-windows.zip"
        }
    }

    try {
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
    } catch {
        Invoke-DiagReleaseCleanup
        return $false
    }

    if ($needsSha) {
        try {
            Invoke-WebRequest -Uri "$url.sha256" -OutFile $shaPath -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "Error: Failed to download SHA256 sidecar for helpers release archive." -ForegroundColor Red
            Invoke-DiagReleaseCleanup
            return $false
        }
        if (-not (Test-Path -Path $shaPath)) {
            Write-Host "Error: SHA256 sidecar for helpers release archive was not downloaded." -ForegroundColor Red
            Invoke-DiagReleaseCleanup
            return $false
        }
        $expectedSha = ((Get-Content -Path $shaPath -Raw).Trim() -split '\s+')[0]
        if ($expectedSha -notmatch '^[0-9a-fA-F]{64}$') {
            Write-Host "Error: SHA256 sidecar for helpers release archive is invalid." -ForegroundColor Red
            Invoke-DiagReleaseCleanup
            return $false
        }
        $actualSha = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
        if ($actualSha.ToLowerInvariant() -ne $expectedSha.ToLowerInvariant()) {
            Write-Host "Error: SHA256 checksum mismatch for helpers release archive." -ForegroundColor Red
            Invoke-DiagReleaseCleanup
            return $false
        }
    }

    try {
        New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force -ErrorAction Stop
        if ($track -eq 'main') {
            $nested = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
            if ($nested -and (Test-Path (Join-Path $nested.FullName 'scripts\windows'))) {
                $script:DiagReleaseExtract = $nested.FullName
                return $true
            }
        }
        $script:DiagReleaseExtract = $extractDir
        return $true
    } catch {
        Invoke-DiagReleaseCleanup
        return $false
    }
}

function Get-ReleaseSourcePath {
    param([string]$RelativePath)
    if (!$script:DiagReleaseExtract) { return $null }
    $full = Join-Path -Path $script:DiagReleaseExtract -ChildPath $RelativePath
    if (Test-Path -Path $full) { return $full }
    return $null
}
