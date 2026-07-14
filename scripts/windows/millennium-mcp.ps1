# Millennium MCP server wrapper — Go-only (Parallel hatch retirement).
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

$exeCandidates = @(
    (Join-Path -Path $ScriptDir -ChildPath 'millennium.exe'),
    (Join-Path -Path $ScriptDir -ChildPath '..\..\bin\millennium.exe'),
    (Join-Path -Path $ScriptDir -ChildPath '..\millennium.exe')
)
$exe = $null
foreach ($cand in $exeCandidates) {
    if (Test-Path -LiteralPath $cand -PathType Leaf) {
        $exe = (Resolve-Path -LiteralPath $cand).Path
        break
    }
}
if (-not $exe) {
    foreach ($name in @('millennium.exe', 'millennium')) {
        $cmd = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($cmd) { $exe = $cmd.Source; break }
    }
}

if (-not $exe) {
    Write-Error "Error: millennium MCP requires millennium.exe (not found). Re-run install.ps1 or make build."
    exit 1
}

$mcpArgs = @('mcp')
if ($Help) { $mcpArgs += '--help' }
if ($Version) { $mcpArgs += '--version' }
if ($Register) { $mcpArgs += '--register' }
if ($Rest) { $mcpArgs += $Rest }

& $exe @mcpArgs
exit $LASTEXITCODE
