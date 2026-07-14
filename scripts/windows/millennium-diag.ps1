# Diagnostics for Millennium helpers — thin-wrap to Go (Phase 6z).
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs = @(),
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
Usage: millennium-diag.ps1 [doctor|logs] [-Json] [-Share] [-DryRun] [-Yes] [-Follow] [-Force] [-Quiet] [-Version] [-Help]

Run Millennium Helpers diagnostics (thin-wrap to Go).

Options:
  doctor / -Fix   Auto-repair
  logs            Show recent logs
  -Json           Structured JSON report
  -Share          Upload redacted report
  -DryRun         Doctor plan only
  -Yes            Allow stopping Steam
  -Follow         Tail logs (with logs)
  -Force          Force doctor repairs
  -Quiet          Suppress info output
  -Version, -V    Show version
  -Help, -h       Show this help
"@
    exit 0
}

if ($Version) {
    Write-HelpersVersion -Name "millennium-diag"
    exit 0
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
    Write-Error "diag requires the Go millennium dispatcher (not found). Install millennium-helpers or run 'make build'."
    exit 1
}

$goArgs = [System.Collections.Generic.List[string]]::new()
[void]$goArgs.Add('diag')
foreach ($a in $RemainingArgs) {
    [void]$goArgs.Add([string]$a)
}
# Preserve unbound args ($args) for GNU-style callers.
if ($args.Count -gt 0) {
    foreach ($a in $args) { [void]$goArgs.Add([string]$a) }
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
