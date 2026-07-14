# Millennium client uninstaller — thin-wrap to Go (Phase 6r).
param(
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

$ScriptDir = $PSScriptRoot
$CommonPs1 = Join-Path -Path $ScriptDir -ChildPath "common.ps1"
if (Test-Path -Path $CommonPs1) {
    . $CommonPs1
} else {
    Write-Error "Shared helper library not found at $CommonPs1"
    exit 1
}

if ($Help) {
    Write-Host @"
Usage: millennium-purge.ps1 [-DryRun] [-Yes] [-Quiet] [-Version] [-Help]

De-register and purge Millennium client hooks and files from Steam.

Options:
  -DryRun, -d     Simulate operations without modifying files
  -Yes, -y        Skip the interactive confirmation prompt
  -Quiet, -q      Suppress informational output
  -Version, -V    Show version information
  -Help, -h       Show this help message
"@
    exit 0
}

if ($Version) {
    Write-HelpersVersion -Name "millennium-purge"
    exit 0
}

if ($Quiet) {
    $global:Quiet = $true
    $env:MILLENNIUM_QUIET = "1"
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

$goBin = Resolve-MillenniumGo
if (-not $goBin) {
    Write-Error "purge requires the Go millennium dispatcher (not found). Install millennium-helpers or run 'make build'."
    exit 1
}

$goArgs = [System.Collections.Generic.List[string]]::new()
[void]$goArgs.Add('purge')
if ($DryRun) { [void]$goArgs.Add('--dry-run') }
if ($Yes) { [void]$goArgs.Add('--yes') }
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
