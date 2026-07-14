# Configure Windows Task Scheduler for Millennium helper auto-updates
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$Command = $null,
    # Catch "config set …" / "enable beta" without binding them to -Channel.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs = @(),
    [ValidateSet("stable", "beta", "main")]
    [string]$Channel = $null,
    [switch]$DryRun = $false,
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

# Remaining positional args after Command (e.g. config set key value, enable beta)
$script:PositionalArgs = @()

# Unbound tokens from ValueFromRemainingArguments (and any classic $args if present)
$unbound = [System.Collections.Generic.List[string]]::new()
foreach ($r in @($RemainingArgs)) {
    if ($null -ne $r -and "$r" -ne "") { [void]$unbound.Add([string]$r) }
}
if (Get-Variable -Name args -ErrorAction SilentlyContinue) {
    foreach ($a in @($args)) {
        if ($null -ne $a -and "$a" -ne "") { [void]$unbound.Add([string]$a) }
    }
}

if ($unbound.Count -gt 0) {
    $gnuFlags = @{
        DryRun  = [bool]$DryRun
        Quiet   = [bool]$Quiet
        Help    = [bool]$Help
        Version = [bool]$Version
        Channel = $Channel
    }
    $remaining = @(Apply-GnuStyleArgs -InputArgs @($unbound.ToArray()) -Target $gnuFlags)
    if ($gnuFlags.DryRun) { $DryRun = $true }
    if ($gnuFlags.Quiet) { $Quiet = $true; $global:Quiet = $true; $env:MILLENNIUM_QUIET = "1" }
    if ($gnuFlags.Help) { $Help = $true }
    if ($gnuFlags.Version) { $Version = $true }
    if ($gnuFlags.Channel) { $Channel = [string]$gnuFlags.Channel }
    if ($remaining.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($Command)) {
            $Command = $remaining[0]
            if ($remaining.Count -gt 1) {
                $script:PositionalArgs = @($remaining[1..($remaining.Count - 1)])
            }
        } else {
            $script:PositionalArgs = @($remaining)
        }
    }
}

if ($Quiet) {
    $global:Quiet = $true
    $env:MILLENNIUM_QUIET = "1"
}

if ($DryRun) {
    $global:DryRun = $true
}

$taskName = "MillenniumUpdate"
$configDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
$configFile = Join-Path -Path $configDir -ChildPath "config.json"
$updaterLog = Join-Path -Path $configDir -ChildPath "updater.log"

# Default channel from config when not set via -Channel / --channel / enable arg
if ([string]::IsNullOrWhiteSpace($Channel)) {
    $Channel = "stable"
    if (Test-Path -Path $configFile) {
        try {
            $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            if ($config -and $config.update_channel) {
                $cand = [string]$config.update_channel
                if (Test-ValidUpdateChannel -Channel $cand) {
                    $Channel = $cand
                } else {
                    Log-Warn "Ignoring invalid update_channel '$cand' in config (expected stable|beta|main)."
                }
            }
        } catch {}
    }
}

# enable <channel> from remaining positionals
if ($Command -eq "enable" -and $script:PositionalArgs.Count -gt 0) {
    $cand = [string]$script:PositionalArgs[0]
    if (Test-ValidUpdateChannel -Channel $cand) {
        $Channel = $cand
    }
}

try {
    $Channel = Require-UpdateChannel -Channel $Channel
} catch {
    Log-Error $_.Exception.Message
    exit 1
}

function Show-Help {
    $helpText = @"
Usage: millennium-schedule COMMAND [ARGUMENTS] [OPTIONS]

Commands:
  enable [stable|beta|main]  Enable the daily update scheduler task (defaults to stable)
  disable               Disable the scheduled update task
  status                Show status of the update scheduler task
  setup                 Run the interactive configuration wizard
  config [get/set/list] Manage Millennium Helper configuration options

Options:
  -d, -DryRun           Perform dry-run without changing Task Scheduler or writing files
  -q, -Quiet            Suppress informational output
  -V, -Version          Show version information
  -h, -Help             Show this help message

GNU-style flags (--dry-run, --quiet) are also accepted.
"@
    Write-Output $helpText
}

if ($Help -or $Command -eq "help" -or $Command -eq "--help" -or $Command -eq "-h") {
    Show-Help
    exit 0
}
if ($Version -or $Command -eq "version" -or $Command -eq "--version" -or $Command -eq "-V") {
    Write-HelpersVersion -Name "millennium-schedule"
    exit 0
}

# Feature modules (dot-sourced by this entrypoint — no thin aggregator)
$script:ScheduleLibDir = Join-Path -Path $ScriptDir -ChildPath 'lib'
. (Join-Path -Path $script:ScheduleLibDir -ChildPath 'ScheduleEnable.ps1')
. (Join-Path -Path $script:ScheduleLibDir -ChildPath 'ScheduleDisable.ps1')
. (Join-Path -Path $script:ScheduleLibDir -ChildPath 'ScheduleWizard.ps1')

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

function Invoke-ScheduleViaGo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Feature,
        [Parameter(Mandatory = $true)]
        [string[]]$GoArgs
    )
    $goBin = Resolve-MillenniumGo
    if (-not $goBin) {
        Write-Error "schedule $Feature requires the Go millennium dispatcher (not found). Install millennium-helpers or run 'make build'."
        exit 1
    }
    $prevLegacy = $env:MILLENNIUM_LEGACY
    $env:MILLENNIUM_LEGACY = '0'
    try {
        & $goBin @GoArgs
        exit $LASTEXITCODE
    } finally {
        if ($null -eq $prevLegacy) {
            Remove-Item Env:MILLENNIUM_LEGACY -ErrorAction SilentlyContinue
        } else {
            $env:MILLENNIUM_LEGACY = $prevLegacy
        }
    }
}

function Invoke-ScheduleConfigViaGo {
    $goArgs = [System.Collections.Generic.List[string]]::new()
    [void]$goArgs.Add('schedule')
    [void]$goArgs.Add('config')
    if ($DryRun -or $global:DryRun) { [void]$goArgs.Add('--dry-run') }
    if ($Quiet) { [void]$goArgs.Add('--quiet') }
    foreach ($a in @($script:PositionalArgs)) {
        if ($null -ne $a -and "$a" -ne '') { [void]$goArgs.Add([string]$a) }
    }
    if ($goArgs.Count -eq 2) {
        [void]$goArgs.Add('list')
    }
    Invoke-ScheduleViaGo -Feature 'config' -GoArgs @($goArgs.ToArray())
}

function Invoke-ScheduleStatusViaGo {
    $goArgs = [System.Collections.Generic.List[string]]::new()
    [void]$goArgs.Add('schedule')
    [void]$goArgs.Add('status')
    if ($Quiet) { [void]$goArgs.Add('--quiet') }
    Invoke-ScheduleViaGo -Feature 'status' -GoArgs @($goArgs.ToArray())
}

# --- Dispatcher ---

switch ($Command) {
    "enable" {
        Enable-Task $Channel
    }
    "disable" {
        Disable-Task
    }
    "status" {
        Invoke-ScheduleStatusViaGo
    }
    "setup" {
        Run-Setup-Wizard
    }
    "config" {
        Invoke-ScheduleConfigViaGo
    }
    Default {
        if ($Command) {
            Log-Error "Unknown command: $Command"
            $suggestion = Get-ClosestToken -InputToken $Command -Candidates @("enable", "disable", "status", "setup", "config")
            if ($suggestion) {
                Write-Host "Did you mean '$suggestion'?"
            }
            Write-Host "Try 'millennium-schedule -Help' for usage."
        } else {
            Show-Help
        }
        exit 1
    }
}
exit 0
