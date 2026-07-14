# Millennium Theme Manager for Windows — thin-wrap to Go (Phase 6g).
param(
    [string]$Command = $null,
    [string]$Theme = $null,
    [switch]$All = $false,
    [switch]$Json = $false,
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

# Source shared helpers
$ScriptDir = $PSScriptRoot
$CommonPs1 = Join-Path -Path $ScriptDir -ChildPath "common.ps1"
if (Test-Path -Path $CommonPs1) {
    . $CommonPs1
} else {
    Write-Error "Shared helper library not found at $CommonPs1"
    exit 1
}

function Show-Help {
    Write-Output @"
Usage: millennium-theme COMMAND [ARGUMENTS] [OPTIONS]

Commands:
  list                  List all installed Millennium themes
  install [owner/repo]  Install a theme from a GitHub repository
  update [theme-name]   Update an installed theme to its latest commit
  remove [theme-name]   Uninstall/remove an installed theme

Options:
  -Json                 Output list command results in structured JSON format
  -d, -DryRun           Perform a dry-run (simulates operations without modifying files)
  -y, -Yes              Skip confirmation when removing a theme
  -q, -Quiet            Suppress informational output
  -V, -Version          Show version information
  -h, -Help             Show this help message

GNU-style flags (--json, --dry-run, --yes, --quiet) are also accepted.

Examples:
  millennium theme install SteamClientHomebrew/millennium-steam-skin
  millennium theme list
"@
}

# Resolve command positional parameters / GNU-style flags from unbound args
if ($args.Count -gt 0) {
    $gnuFlags = @{
        Json = [bool]$Json
        DryRun = [bool]$DryRun
        Yes = [bool]$Yes
        Quiet = [bool]$Quiet
        Help = [bool]$Help
        Version = [bool]$Version
        All = [bool]$All
    }
    $remaining = Apply-GnuStyleArgs -InputArgs ([string[]]$args) -Target $gnuFlags
    if ($gnuFlags.Json) { $Json = $true }
    if ($gnuFlags.DryRun) { $DryRun = $true }
    if ($gnuFlags.Yes) { $Yes = $true }
    if ($gnuFlags.Quiet) { $Quiet = $true; $global:Quiet = $true; $env:MILLENNIUM_QUIET = "1" }
    if ($gnuFlags.Help) { $Help = $true }
    if ($gnuFlags.Version) { $Version = $true }
    if ($gnuFlags.All) { $All = $true }
    if ($remaining.Count -gt 0) {
        if (!$Command) { $Command = $remaining[0] }
        if ($remaining.Count -gt 1 -and !$Theme) {
            if ($remaining[1] -ne "-a" -and $remaining[1] -ne "--all") {
                $Theme = $remaining[1]
            } else {
                $All = $true
            }
        }
    }
}

if ($Quiet) {
    $global:Quiet = $true
    $env:MILLENNIUM_QUIET = "1"
}

if ($Help -or $Command -eq "help" -or $Command -eq "--help" -or $Command -eq "-h") {
    Show-Help
    exit 0
}
if ($Version -or $Command -eq "version" -or $Command -eq "--version" -or $Command -eq "-V") {
    Write-HelpersVersion -Name "millennium-theme"
    exit 0
}

$knownCommands = @("list", "install", "update", "remove")
if (-not $Command) {
    Show-Help
    exit 1
}
if ($knownCommands -notcontains $Command) {
    Log-Error "Unknown command: $Command"
    $suggestion = Get-ClosestToken -InputToken $Command -Candidates $knownCommands
    if ($suggestion) {
        Write-Host "Did you mean '$suggestion'?"
    }
    Write-Host "Try 'millennium-theme -Help' for usage."
    exit 1
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

function Invoke-ThemeViaGo {
    $goBin = Resolve-MillenniumGo
    if (-not $goBin) {
        Write-Error "theme requires the Go millennium dispatcher (not found). Install millennium-helpers or run 'make build'."
        exit 1
    }
    $goArgs = [System.Collections.Generic.List[string]]::new()
    [void]$goArgs.Add('theme')
    [void]$goArgs.Add($Command)
    if ($DryRun -or $global:DryRun) { [void]$goArgs.Add('--dry-run') }
    if ($Quiet) { [void]$goArgs.Add('--quiet') }
    if ($Yes) { [void]$goArgs.Add('--yes') }
    if ($Json) { [void]$goArgs.Add('--json') }
    if ($All -and $Command -eq 'update') {
        [void]$goArgs.Add('--all')
    } elseif ($Theme) {
        [void]$goArgs.Add([string]$Theme)
    }
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
}

Invoke-ThemeViaGo
