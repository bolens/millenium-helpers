# Millennium MCP server wrapper — prefer Go dispatcher, Python escape hatch.
param(
    [Alias("r")]
    [switch]$Register = $false,
    [Alias("V")]
    [switch]$Version = $false,
    [Alias("h")]
    [switch]$Help = $false,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)
set-strictmode -version Latest

$ScriptDir = $PSScriptRoot
$forcePython = $env:MILLENNIUM_MCP_PYTHON -in @('1', 'true', 'yes') -or $env:MILLENNIUM_LEGACY -in @('1', 'true', 'yes')

$exeCandidates = @(
    (Join-Path -Path $ScriptDir -ChildPath 'millennium.exe'),
    (Join-Path -Path $ScriptDir -ChildPath 'windows\millennium.exe')
)
$exe = $null
foreach ($cand in $exeCandidates) {
    if (Test-Path -LiteralPath $cand -PathType Leaf) {
        $exe = $cand
        break
    }
}

$mcpArgs = @()
if ($Help) { $mcpArgs += '--help' }
if ($Version) { $mcpArgs += '--version' }
if ($Register) { $mcpArgs += '--register' }
if ($Rest) { $mcpArgs += $Rest }

if (-not $forcePython -and $exe) {
    $goArgs = @('mcp') + $mcpArgs
    & $exe @goArgs
    exit $LASTEXITCODE
}

$PyCandidates = @(
    (Join-Path -Path $ScriptDir -ChildPath "millennium-mcp.py"),
    (Join-Path -Path $ScriptDir -ChildPath "..\millennium-mcp.py")
)

$pyScript = $null
foreach ($cand in $PyCandidates) {
    if (Test-Path -Path $cand -PathType Leaf) {
        $pyScript = $cand
        break
    }
}

if (-not $pyScript) {
    Write-Error "Error: millennium.exe / millennium-mcp.py not found next to this wrapper. Re-run install.ps1."
    exit 1
}

$python = $null
foreach ($name in @("python3", "python", "py")) {
    $cmd = Get-Command -Name $name -ErrorAction SilentlyContinue
    if ($cmd) {
        $python = $cmd.Source
        break
    }
}
if (-not $python) {
    Write-Error "Error: Python 3 is required for the MCP Python escape hatch. Install Python or place millennium.exe beside this wrapper."
    exit 1
}

$pyArgs = @($pyScript) + $mcpArgs
& $python @pyArgs
exit $LASTEXITCODE
