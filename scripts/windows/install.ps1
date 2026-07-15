# Thin bootstrap: ensure millennium.exe, then invoke millennium install|uninstall.
param(
    [switch]$Uninstall,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Help,
    [switch]$Version,
    [switch]$AllowUnsignedMain,
    [ValidateSet('release', 'main', 'tag')]
    [string]$Track = $(if ($env:MILLENNIUM_HELPERS_TRACK) { $env:MILLENNIUM_HELPERS_TRACK } else { 'release' }),
    [string]$Tag = $(if ($env:MILLENNIUM_HELPERS_TAG) { $env:MILLENNIUM_HELPERS_TAG } else { '' })
)

$ErrorActionPreference = 'Stop'
$srcDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $srcDir '..\..')).Path

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

# Piped / standalone: no VERSION beside repo → download zip and re-exec.
$versionFile = Join-Path $repoRoot 'VERSION'
if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    Write-Host "Standalone/piped Windows bootstrap is not implemented in this thin installer."
    Write-Host "Use a checkout, release zip with VERSION + scripts\windows\, or install via Scoop/Winget."
    exit 1
}

$exe = Get-MillenniumExe
$env:MILLENNIUM_SOURCE_ROOT = $repoRoot

$fwd = @()
if ($DryRun) { $fwd += '--dry-run' }
if ($Force) { $fwd += '--force' }
if ($AllowUnsignedMain) { $fwd += '--allow-unsigned-main' }
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
