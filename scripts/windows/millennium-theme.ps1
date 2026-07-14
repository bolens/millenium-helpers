# Millennium Theme Manager for Windows — thin-wrap to Go.
param(
    [Parameter(Position = 0)]
    [string]$Command = $null,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs = @(),
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

if ($Help -or $Command -eq 'help') {
    Write-Host @"
Usage: millennium-theme COMMAND [ARGUMENTS] [OPTIONS]

Commands: list, install, update, remove
Options: -Json, -DryRun, -Yes, -Quiet, -Version, -Help

GNU-style flags (--json, --dry-run, --yes, --quiet) are also accepted.

Examples:
  millennium-theme install SteamClientHomebrew/millennium-steam-skin
  millennium-theme list -Json
"@
    exit 0
}

$goBin = Resolve-MillenniumGo
if ($Version -or $Command -eq 'version') {
    if ($goBin) { & $goBin theme -V; exit $LASTEXITCODE }
    $verFile = Join-Path $ScriptDir '..\..\VERSION'
    if (Test-Path -LiteralPath $verFile) {
        Write-Host ("millennium-theme " + ((Get-Content -LiteralPath $verFile -Raw).Trim()))
        exit 0
    }
    Write-Error "millennium not found (and no VERSION file)."
    exit 1
}

if (-not $Command) {
    Write-Host "Usage: millennium-theme COMMAND ..."
    exit 1
}

if (-not $goBin) {
    Write-Error "theme requires the Go millennium dispatcher (not found)."
    exit 1
}

$goArgs = [System.Collections.Generic.List[string]]::new()
[void]$goArgs.Add('theme')
[void]$goArgs.Add($Command)
foreach ($a in @($RemainingArgs)) {
    if ($null -ne $a -and "$a" -ne '') { [void]$goArgs.Add([string]$a) }
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
