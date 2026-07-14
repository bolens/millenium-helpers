# Dispatcher for Millennium Helpers: millennium <command> [args...]
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

# Feature modules (dot-sourced by this entrypoint — no thin aggregator).
# Intentionally does not source common.ps1 so the dispatcher stays lightweight.
. (Join-Path -Path $ScriptDir -ChildPath 'lib\Dispatcher.ps1')

# Natural alias: millennium doctor -> millennium-diag doctor
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
        Write-Host "Unknown command: $Command"
        $suggestion = Get-CommandSuggestion -InputCmd $Command
        if ($suggestion) {
            Write-Host "Did you mean '$suggestion'?"
        }
        Write-Host "Run 'millennium help' for usage."
        exit 1
    }
}
