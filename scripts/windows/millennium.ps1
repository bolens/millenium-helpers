# Thin dispatcher for Millennium Helpers: millennium <command> [args...]
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)
set-strictmode -version Latest

$ScriptDir = $PSScriptRoot

function Show-Help {
    Write-Output @"
Usage: millennium <command> [args...]

Commands:
  diag       Run diagnostics (millennium-diag)
  doctor     Alias for: diag doctor
  upgrade    Upgrade / install Millennium (millennium-upgrade)
  schedule   Manage auto-update scheduler (millennium-schedule)
  theme      Manage skins/themes (millennium-theme)
  repair     Repair hooks and ownership (millennium-repair)
  purge      Uninstall Millennium (millennium-purge)
  mcp        Run / register the MCP server (millennium-mcp)
  help       Show this help

Examples:
  millennium diag
  millennium doctor
  millennium upgrade -Channel beta
  millennium schedule status
  millennium theme list
"@
}

function Get-CommandSuggestion {
    param([string]$InputCmd)
    $cmds = @("diag", "doctor", "upgrade", "schedule", "theme", "repair", "purge", "mcp", "help")
    $best = $null
    $bestScore = 0
    foreach ($c in $cmds) {
        $score = 0
        if ($c -eq $InputCmd) { return $c }
        if ($c.StartsWith($InputCmd) -or $InputCmd.StartsWith($c)) {
            $score = 3
        } elseif ($c.Contains($InputCmd) -or $InputCmd.Contains($c)) {
            $score = 2
        } else {
            $i = 0
            while ($i -lt $c.Length -and $i -lt $InputCmd.Length -and $c[$i] -eq $InputCmd[$i]) {
                $i++
            }
            $score = $i
        }
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $c
        }
    }
    if ($bestScore -ge 2) { return $best }
    return $null
}

function Invoke-Sibling {
    param(
        [string]$Name,
        [string[]]$ArgsList
    )
    $scriptPath = Join-Path -Path $ScriptDir -ChildPath "$Name.ps1"
    if (!(Test-Path -Path $scriptPath)) {
        $cmd = Get-Command -Name "$Name.ps1" -ErrorAction SilentlyContinue
        if ($cmd) {
            $scriptPath = $cmd.Source
        } else {
            Write-Error "Error: '$Name' not found."
            exit 1
        }
    }
    & $scriptPath @ArgsList
    exit $LASTEXITCODE
}

# Natural alias: millennium doctor → millennium-diag doctor
if ($Command -eq "doctor") {
    $Rest = @("doctor") + @($Rest)
    $Command = "diag"
}

switch -Regex ($Command) {
    '^(help|-h|--help)$' {
        Show-Help
        exit 0
    }
    '^(-V|--version)$' {
        $diag = Join-Path -Path $ScriptDir -ChildPath "millennium-diag.ps1"
        if (Test-Path -Path $diag) {
            & $diag -Version
            exit $LASTEXITCODE
        }
        Write-Output "millennium (dispatcher)"
        exit 0
    }
    '^(diag|upgrade|schedule|theme|repair|purge|mcp)$' {
        Invoke-Sibling -Name "millennium-$Command" -ArgsList $Rest
    }
    Default {
        Write-Error "Unknown command: $Command"
        $suggestion = Get-CommandSuggestion -InputCmd $Command
        if ($suggestion) {
            Write-Host "Did you mean '$suggestion'?"
        }
        Write-Host "Run 'millennium help' for usage."
        exit 1
    }
}
