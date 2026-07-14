# Millennium client uninstaller and files purge utility on Windows
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

# Source shared helpers
$ScriptDir = $PSScriptRoot
$CommonPs1 = Join-Path -Path $ScriptDir -ChildPath "common.ps1"
if (Test-Path -Path $CommonPs1) {
    . $CommonPs1
} else {
    Write-Error "Shared helper library not found at $CommonPs1"
    exit 1
}

if ($Version) {
    Write-HelpersVersion -Name "millennium-purge"
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
. (Join-Path -Path $ScriptDir -ChildPath 'lib\PurgeOps.ps1')

Invoke-MillenniumPurge
exit 0
