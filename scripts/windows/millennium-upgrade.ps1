# Millennium upgrade — thin-wrap to Go.
param(
    [ValidateSet("stable", "beta", "main")]
    [string]$Channel = "stable",
    [switch]$Force = $false,
    [string]$File = $null,
    [string]$Sha256 = $null,
    [switch]$InsecureSkipVerify = $false,
    [string]$Rollback = $null,
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

if ($Help) {
    Write-Host @"
Usage: millennium-upgrade.ps1 [-Channel stable|beta|main] [-Force] [-File PATH] [-Sha256 HEX]
       [-InsecureSkipVerify] [-Rollback ID|list] [-DryRun] [-Yes] [-Quiet] [-Version] [-Help]

Install official Millennium releases (via Go).

GNU-style flags (--channel, --force, --file, --rollback, --dry-run, --yes) are also accepted.
"@
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
if ($Version) {
    if ($goBin) {
        & $goBin -V
        exit $LASTEXITCODE
    }
    $verFile = Join-Path $ScriptDir '..\..\VERSION'
    if (Test-Path -LiteralPath $verFile) {
        Write-Host ("millennium-upgrade " + ((Get-Content -LiteralPath $verFile -Raw).Trim()))
        exit 0
    }
    Write-Error "millennium not found (and no VERSION file)."
    exit 1
}

if (-not $goBin) {
    Write-Error "upgrade requires the Go millennium dispatcher (not found). Install millennium-helpers or run 'make build'."
    exit 1
}

$goArgs = [System.Collections.Generic.List[string]]::new()
[void]$goArgs.Add('upgrade')
if ($MyInvocation.BoundParameters.ContainsKey('Channel')) {
    [void]$goArgs.Add('--channel'); [void]$goArgs.Add($Channel)
}
if ($Force) { [void]$goArgs.Add('--force') }
if ($File) { [void]$goArgs.Add('--file'); [void]$goArgs.Add($File) }
if ($Sha256) { [void]$goArgs.Add('--sha256'); [void]$goArgs.Add($Sha256) }
if ($InsecureSkipVerify) { [void]$goArgs.Add('--insecure-skip-verify') }
if ($null -ne $Rollback -and "$Rollback" -ne '') {
    [void]$goArgs.Add('--rollback'); [void]$goArgs.Add([string]$Rollback)
}
if ($DryRun) { [void]$goArgs.Add('--dry-run') }
if ($Yes) { [void]$goArgs.Add('--yes') }
if ($Quiet) { [void]$goArgs.Add('--quiet') }
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
