# Millennium Client Force Reinstall and Repair utility on Windows
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

# Source shared helpers
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

Force reinstall the Millennium client on Windows (via millennium-upgrade -Force),
optionally refresh installed themes, and re-register the auto-update task if present.

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

if ($Yes) {
    $global:AssumeYes = $true
}

if ($Quiet) {
    $global:Quiet = $true
    $env:MILLENNIUM_QUIET = "1"
}

if ($DryRun) {
    $global:DryRun = $true
}


# Feature modules (dot-sourced by this entrypoint — no thin aggregator)
. (Join-Path -Path $ScriptDir -ChildPath 'lib\RepairOps.ps1')

Invoke-MillenniumRepair
exit 0
