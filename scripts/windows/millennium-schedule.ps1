# Configure Windows Task Scheduler — thin-wrap to Go.
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$Command = $null,
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

$ScriptDir = $PSScriptRoot

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

if ($Help) {
    Write-Host @"
Usage: millennium-schedule.ps1 <Command> [options]

Commands: enable, disable, status, setup, config, pre-update, post-update
Options: -Channel, -DryRun, -Quiet, -Version, -Help

GNU-style flags (--channel, --dry-run, --quiet) are also accepted.
"@
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Command)) {
    Write-Host "Usage: millennium-schedule.ps1 <Command> [options]"
    exit 1
}

$goBin = Resolve-MillenniumGo
if ($Version) {
    if ($goBin) { & $goBin schedule -V; exit $LASTEXITCODE }
    $verFile = Join-Path $ScriptDir '..\..\VERSION'
    if (Test-Path -LiteralPath $verFile) {
        Write-Host ("millennium-schedule " + ((Get-Content -LiteralPath $verFile -Raw).Trim()))
        exit 0
    }
    Write-Error "millennium not found (and no VERSION file)."
    exit 1
}

if (-not $goBin) {
    Write-Error "schedule requires the Go millennium dispatcher (not found)."
    exit 1
}

$goArgs = [System.Collections.Generic.List[string]]::new()
[void]$goArgs.Add('schedule')
[void]$goArgs.Add($Command)
if ($Channel) { [void]$goArgs.Add('--channel'); [void]$goArgs.Add($Channel) }
if ($DryRun) { [void]$goArgs.Add('--dry-run') }
if ($Quiet) { [void]$goArgs.Add('--quiet') }
foreach ($r in @($RemainingArgs)) {
    if ($null -ne $r -and "$r" -ne '') { [void]$goArgs.Add([string]$r) }
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
