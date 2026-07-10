# Millennium MCP server wrapper for Windows (invokes millennium-mcp.py)
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
    Write-Error "Error: millennium-mcp.py not found next to this wrapper. Re-run install.ps1."
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
    Write-Error "Error: Python 3 is required to run millennium-mcp. Install Python and retry."
    exit 1
}

$argList = @($pyScript)
if ($Help) { $argList += "--help" }
if ($Version) { $argList += "--version" }
if ($Register) { $argList += "--register" }
if ($Rest) { $argList += $Rest }

& $python @argList
exit $LASTEXITCODE
