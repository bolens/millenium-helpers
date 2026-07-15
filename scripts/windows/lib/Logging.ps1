# Logging.ps1 - Quiet detection, debug/log helpers, dry-run execute, file writers

function Test-MillenniumQuiet {
    return ($global:Quiet -eq $true) -or [bool]$env:MILLENNIUM_QUIET
}

function Write-DebugMsg {
    param([string]$Msg)
    $debugEnabled = $env:MILLENNIUM_DEBUG -or ($VerbosePreference -eq 'Continue')
    if ($debugEnabled) {
        Write-Host "DEBUG: $Msg"
    }
}


function Log-Msg {
    param(
        [string]$Level,
        [string]$Msg
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $scriptName = $MyInvocation.ScriptName
    if ($scriptName) {
        $scriptName = Split-Path -Leaf $scriptName
    } else {
        $scriptName = "interactive"
    }
    Write-Host "[$timestamp] [$Level] [$scriptName] $Msg"
}


function Log-Info {
    param([string]$Msg)
    if (Test-MillenniumQuiet) { return }
    Log-Msg -Level "INFO" -Msg $Msg
}


function Log-Warn {
    param([string]$Msg)
    Log-Msg -Level "WARN" -Msg $Msg
}


function Log-Error {
    param([string]$Msg)
    Log-Msg -Level "ERROR" -Msg "$RED$Msg$NC"
}


function Execute-Cmd {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Description
    )
    if ($global:DryRun) {
        Write-Host "${YELLOW}[DRY RUN] Would run:${NC} $Description"
    } else {
        & $ScriptBlock
    }
}


function Write-ContentFile {
    param(
        [string]$Path,
        [string]$Content
    )
    if ($global:DryRun) {
        Write-Host "${YELLOW}[DRY RUN] Would write file: $Path with contents:${NC}"
        Write-Host $Content
    } else {
        $parent = Split-Path -Parent $Path
        if ($parent -and !(Test-Path -Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Set-Content -Path $Path -Value $Content -Force
    }
}


function Write-UpgradeFailureTips {
    param([string]$Detail = "")
    Write-Host ""
    if ($Detail) {
        Log-Error "Upgrade failed: $Detail"
    } else {
        Log-Error "Upgrade failed."
    }
    Write-Host "Next steps:"
    Write-Host "  * millennium upgrade -Rollback list   # list backups"
    Write-Host "  * millennium diag                     # check installation health"
    Write-Host "  * Re-run with -Yes if Steam close confirmation blocked the update"
}
