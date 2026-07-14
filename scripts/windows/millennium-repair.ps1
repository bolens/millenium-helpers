# Millennium repair — thin-wrap to Go (Phase 6ad).
param(
    [switch]$DryRun = $false,
    [Alias("y")]
    [switch]$Yes = $false,
    [Alias("q")]
    [switch]$Quiet = $false,
    [Alias("s")]
    [switch]$SkipTheme = $false,
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

if ($args.Count -gt 0) {
    $gnuFlags = @{
        DryRun    = [bool]$DryRun
        Yes       = [bool]$Yes
        Quiet     = [bool]$Quiet
        SkipTheme = [bool]$SkipTheme
        Help      = [bool]$Help
        Version   = [bool]$Version
    }
    [void](Apply-GnuStyleArgs -InputArgs ([string[]]$args) -Target $gnuFlags)
    if ($gnuFlags.DryRun) { $DryRun = $true }
    if ($gnuFlags.Yes) { $Yes = $true }
    if ($gnuFlags.Quiet) { $Quiet = $true; $global:Quiet = $true; $env:MILLENNIUM_QUIET = "1" }
    if ($gnuFlags.SkipTheme) { $SkipTheme = $true }
    if ($gnuFlags.Help) { $Help = $true }
    if ($gnuFlags.Version) { $Version = $true }
}

if ($Help) {
    Write-Host @"
Usage: millennium-repair.ps1 [-DryRun] [-Yes] [-Quiet] [-SkipTheme] [-Version] [-Help]

Repair Millennium hooks/binaries, ownership, htmlcache, and themes (via Go).

Options:
  -DryRun         Simulate operations without modifying files
  -Yes, -y        Skip confirmation when closing Steam
  -Quiet, -q      Suppress informational output
  -SkipTheme, -s  Skip theme refresh after reinstall
  -Version, -V    Show version information
  -Help, -h       Show this help message

GNU-style flags (--skip-theme, --yes, --quiet, --dry-run) are also accepted.
"@
    exit 0
}

if ($Version) {
    Write-HelpersVersion -Name "millennium-repair"
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
    Write-Error "repair requires the Go millennium dispatcher (not found). Install millennium-helpers or run 'make build'."
    exit 1
}

$goArgs = [System.Collections.Generic.List[string]]::new()
[void]$goArgs.Add('repair')
if ($DryRun) { [void]$goArgs.Add('--dry-run') }
if ($Yes) { [void]$goArgs.Add('--yes') }
if ($Quiet) { [void]$goArgs.Add('--quiet') }
if ($SkipTheme) { [void]$goArgs.Add('--skip-theme') }

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
