# Thin bootstrap: ensure millennium.exe, then invoke millennium install|uninstall.
# Piped (irm|iex): download release/main zip, verify SHA when available, re-exec extracted installer.
param(
    [switch]$Uninstall,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Help,
    [switch]$Version,
    [switch]$AllowUnsignedMain,
    [switch]$SkipWizard,
    [ValidateSet('release', 'main', 'tag')]
    [string]$Track = $(if ($env:MILLENNIUM_HELPERS_TRACK) { $env:MILLENNIUM_HELPERS_TRACK } else { 'release' }),
    [string]$Tag = $(if ($env:MILLENNIUM_HELPERS_TAG) { $env:MILLENNIUM_HELPERS_TAG } else { '' })
)

$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($Tag)) {
    $Track = 'tag'
}
$Track = $Track.ToLowerInvariant()

# Resolve whether we have a real on-disk checkout / release extract.
$scriptPath = ''
if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Definition) {
    $scriptPath = [string]$MyInvocation.MyCommand.Definition
}
$srcDir = $PSScriptRoot
if (-not $srcDir -and $scriptPath -and (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    $srcDir = Split-Path -Parent -Path $scriptPath
}

$isStandalone = $true
$repoRoot = $null
if ($srcDir) {
    try {
        $repoRoot = (Resolve-Path (Join-Path $srcDir '..\..')).Path
        $versionFile = Join-Path $repoRoot 'VERSION'
        if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
            $isStandalone = $false
        }
    } catch {
        $isStandalone = $true
    }
}

if ($isStandalone) {
    Write-Host "Running in standalone/piped mode. Downloading helpers (track=$Track)..."
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("millennium-helpers-temp-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    try {
        $repo = if ($env:HELPERS_GITHUB_REPO) { $env:HELPERS_GITHUB_REPO } else { 'bolens/millenium-helpers' }
        $needsSha = $true
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

        $zipPath = Join-Path $tempDir 'millennium-helpers-download.zip'
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

        if ($needsSha) {
            $shaPath = Join-Path $tempDir 'millennium-helpers-download.zip.sha256'
            try {
                Invoke-WebRequest -Uri $shaUrl -OutFile $shaPath -UseBasicParsing
            } catch {
                throw "Failed to download the SHA256 checksum sidecar (url=$shaUrl): $_"
            }
            if (!(Test-Path -LiteralPath $shaPath -PathType Leaf)) {
                throw "SHA256 checksum sidecar was not downloaded (url=$shaUrl)"
            }
            $expectedSha = ((Get-Content -LiteralPath $shaPath -Raw).Trim() -split '\s+')[0]
            if ([string]::IsNullOrWhiteSpace($expectedSha) -or $expectedSha -notmatch '^[0-9a-fA-F]{64}$') {
                throw "Checksum sidecar did not contain a valid SHA256 hash (url=$shaUrl)"
            }
            $actualSha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
            if ($actualSha.ToLowerInvariant() -ne $expectedSha.ToLowerInvariant()) {
                throw "SHA256 mismatch for downloaded release archive. Expected=$expectedSha Actual=$actualSha"
            }
            Write-Host "SHA256 checksum verified."
        } else {
            Write-Host "Tip-of-main archive: skipping release SHA256 sidecar."
        }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $tempDir -Force

        $extractedScript = Join-Path $tempDir 'scripts\windows\install.ps1'
        if (!(Test-Path -LiteralPath $extractedScript -PathType Leaf)) {
            $extractedFolder = Get-ChildItem -LiteralPath $tempDir -Directory | Select-Object -First 1
            if ($extractedFolder) {
                $extractedScript = Join-Path $extractedFolder.FullName 'scripts\windows\install.ps1'
            }
        }
        if (!(Test-Path -LiteralPath $extractedScript -PathType Leaf)) {
            throw "Archive is missing scripts\windows\install.ps1 (url=$url)"
        }

        $env:MILLENNIUM_HELPERS_TRACK = $Track
        if ($Tag) { $env:MILLENNIUM_HELPERS_TAG = $Tag }
        $env:MILLENNIUM_HELPERS_SOURCE_URL = $url
        if ($AllowUnsignedMain) { $env:MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN = '1' }

        $params = @{}
        if ($Uninstall) { $params['Uninstall'] = $true }
        if ($Force) { $params['Force'] = $true }
        if ($DryRun) { $params['DryRun'] = $true }
        if ($SkipWizard) { $params['SkipWizard'] = $true }
        if ($AllowUnsignedMain) { $params['AllowUnsignedMain'] = $true }
        if ($Track) { $params['Track'] = $Track }
        if ($Tag) { $params['Tag'] = $Tag }

        & $extractedScript @params
        exit $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Get-MillenniumExe {
    $candidates = @(
        (Join-Path $srcDir 'millennium.exe'),
        (Join-Path $repoRoot 'bin\millennium.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    $go = Get-Command go -ErrorAction SilentlyContinue
    $goMain = Join-Path $repoRoot 'go\cmd\millennium'
    if ($go -and (Test-Path -LiteralPath $goMain)) {
        $out = Join-Path $repoRoot 'bin\millennium.exe'
        New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
        Push-Location (Join-Path $repoRoot 'go')
        try {
            & go build -o $out ./cmd/millennium
            if ($LASTEXITCODE -ne 0) { throw 'go build failed' }
        } finally {
            Pop-Location
        }
        if (Test-Path -LiteralPath $out -PathType Leaf) { return $out }
    }
    throw 'Go dispatcher millennium.exe is required (run make build / place bin\millennium.exe).'
}

$exe = Get-MillenniumExe
$env:MILLENNIUM_SOURCE_ROOT = $repoRoot

$fwd = @()
if ($DryRun) { $fwd += '--dry-run' }
if ($Force) { $fwd += '--force' }
if ($AllowUnsignedMain) { $fwd += '--allow-unsigned-main' }
if ($SkipWizard) { $fwd += '--skip-wizard' }
if ($Tag) {
    $fwd += @('--tag', $Tag)
} elseif ($Track) {
    $fwd += @('--track', $Track)
}

if ($Help) {
    & $exe install --help
    exit $LASTEXITCODE
}
if ($Version) {
    & $exe version
    exit $LASTEXITCODE
}

$action = if ($Uninstall) { 'uninstall' } else { 'install' }
& $exe $action @fwd
exit $LASTEXITCODE
