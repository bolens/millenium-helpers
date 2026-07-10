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
  upgrade    Upgrade / install Millennium (millennium-upgrade)
  schedule   Manage auto-update scheduler (millennium-schedule)
  theme      Manage skins/themes (millennium-theme)
  repair     Repair hooks and ownership (millennium-repair)
  purge      Uninstall Millennium (millennium-purge)
  mcp        Run / register the MCP server (millennium-mcp)
  help       Show this help

Examples:
  millennium diag
  millennium upgrade -Channel beta
  millennium schedule status
  millennium theme list
"@
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
        Write-Host "Run 'millennium help' for usage."
        exit 1
    }
}
