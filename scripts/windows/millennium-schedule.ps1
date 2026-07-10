# Configure Windows Task Scheduler for Millennium helper auto-updates
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$Command = $null,
    # Catch "config set …" / "enable beta" without binding them to -Channel.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs = @(),
    [ValidateSet("stable", "beta", "main")]
    [string]$Channel = $null,
    [switch]$DryRun = $false,
    [Alias("q")]
    [switch]$Quiet = $false,
    [Alias("h")]
    [switch]$Help = $false,
    [Alias("V")]
    [switch]$Version = $false
)
set-strictmode -version Latest

# Source shared helpers
$ScriptDir = $PSScriptRoot
$CommonPs1 = Join-Path -Path $ScriptDir -ChildPath "common.ps1"
if (Test-Path -Path $CommonPs1) {
    . $CommonPs1
} else {
    Write-Error "Shared helper library not found at $CommonPs1"
    exit 1
}

# Remaining positional args after Command (e.g. config set key value, enable beta)
$script:PositionalArgs = @()

# Unbound tokens from ValueFromRemainingArguments (and any classic $args if present)
$unbound = [System.Collections.Generic.List[string]]::new()
foreach ($r in @($RemainingArgs)) {
    if ($null -ne $r -and "$r" -ne "") { [void]$unbound.Add([string]$r) }
}
if (Get-Variable -Name args -ErrorAction SilentlyContinue) {
    foreach ($a in @($args)) {
        if ($null -ne $a -and "$a" -ne "") { [void]$unbound.Add([string]$a) }
    }
}

if ($unbound.Count -gt 0) {
    $gnuFlags = @{
        DryRun  = [bool]$DryRun
        Quiet   = [bool]$Quiet
        Help    = [bool]$Help
        Version = [bool]$Version
        Channel = $Channel
    }
    $remaining = @(Apply-GnuStyleArgs -InputArgs @($unbound.ToArray()) -Target $gnuFlags)
    if ($gnuFlags.DryRun) { $DryRun = $true }
    if ($gnuFlags.Quiet) { $Quiet = $true; $global:Quiet = $true; $env:MILLENNIUM_QUIET = "1" }
    if ($gnuFlags.Help) { $Help = $true }
    if ($gnuFlags.Version) { $Version = $true }
    if ($gnuFlags.Channel) { $Channel = [string]$gnuFlags.Channel }
    if ($remaining.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($Command)) {
            $Command = $remaining[0]
            if ($remaining.Count -gt 1) {
                $script:PositionalArgs = @($remaining[1..($remaining.Count - 1)])
            }
        } else {
            $script:PositionalArgs = @($remaining)
        }
    }
}

if ($Quiet) {
    $global:Quiet = $true
    $env:MILLENNIUM_QUIET = "1"
}

if ($DryRun) {
    $global:DryRun = $true
}

$taskName = "MillenniumUpdate"
$configDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
$configFile = Join-Path -Path $configDir -ChildPath "config.json"
$updaterLog = Join-Path -Path $configDir -ChildPath "updater.log"

# Default channel from config when not set via -Channel / --channel / enable arg
if ([string]::IsNullOrWhiteSpace($Channel)) {
    $Channel = "stable"
    if (Test-Path -Path $configFile) {
        try {
            $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            if ($config -and $config.update_channel) {
                $Channel = [string]$config.update_channel
            }
        } catch {}
    }
}

# enable <channel> from remaining positionals
if ($Command -eq "enable" -and $script:PositionalArgs.Count -gt 0) {
    $cand = [string]$script:PositionalArgs[0]
    if ($cand -in @("stable", "beta", "main")) {
        $Channel = $cand
    }
}

function Show-Help {
    $helpText = @"
Usage: millennium-schedule COMMAND [ARGUMENTS] [OPTIONS]

Commands:
  enable [stable|beta|main]  Enable the daily update scheduler task (defaults to stable)
  disable               Disable the scheduled update task
  status                Show status of the update scheduler task
  setup                 Run the interactive configuration wizard
  config [get/set/list] Manage Millennium Helper configuration options

Options:
  -d, -DryRun           Perform dry-run without changing Task Scheduler or writing files
  -q, -Quiet            Suppress informational output
  -V, -Version          Show version information
  -h, -Help             Show this help message

GNU-style flags (--dry-run, --quiet) are also accepted.
"@
    Write-Output $helpText
}

if ($Help -or $Command -eq "help" -or $Command -eq "--help" -or $Command -eq "-h") {
    Show-Help
    exit 0
}
if ($Version -or $Command -eq "version" -or $Command -eq "--version" -or $Command -eq "-V") {
    Write-HelpersVersion -Name "millennium-schedule"
    exit 0
}

function Enable-Task {
    $channel_arg = $args[0]
    $upgradeScript = Join-Path -Path $ScriptDir -ChildPath "millennium-upgrade.ps1"
    $themeScript = Join-Path -Path $ScriptDir -ChildPath "millennium-theme.ps1"

    if (!(Test-Path -Path $upgradeScript)) {
        Log-Error "Error: Millennium upgrade script not found at $upgradeScript"
        exit 1
    }

    if (!(Test-Admin)) {
        Log-Error "Error: Administrator privileges are required to configure Scheduled Tasks."
        exit 1
    }

    Log-Info "Configuring Windows Task Scheduler task '$taskName' ($channel_arg channel)..."

    # Generate random start delay to prevent DDoS on GitHub
    $delayMin = Get-Random -Minimum 0 -Maximum 60

    # Match Unix timer: upgrade -Yes -Quiet, theme update, append to updater.log
    $psInner = @(
        "New-Item -ItemType Directory -Force -Path '$configDir' | Out-Null"
        "& '$upgradeScript' -Channel $channel_arg -Yes -Quiet *>> '$updaterLog'"
        "if (Test-Path -LiteralPath '$themeScript') { & '$themeScript' update -Quiet *>> '$updaterLog' }"
    ) -join "; "
    $taskArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$psInner`""

    Log-Info "Task command: powershell.exe $taskArg"

    Execute-Cmd -ScriptBlock {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArg
        $trigger = New-ScheduledTaskTrigger -Daily -At "2:00AM"
        $trigger.RandomDelay = [System.TimeSpan]::FromMinutes($delayMin)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    } -Description "Register-ScheduledTask -TaskName $taskName"

    Log-Info "Millennium auto-update scheduled task has been enabled!"
    Log-Info "It will run daily with a randomized delay of up to 1 hour."
    Log-Info "Logs append to: $updaterLog"
}

function Disable-Task {
    if (!(Test-Admin)) {
        Log-Error "Error: Administrator privileges are required to remove Scheduled Tasks."
        exit 1
    }

    Log-Info "Disabling and removing scheduled task '$taskName'..."
    Execute-Cmd -ScriptBlock {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -ne $task) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Log-Info "Scheduled task '$taskName' has been removed."
        } else {
            Log-Info "No scheduled task found to disable."
        }
    } -Description "Unregister-ScheduledTask -TaskName $taskName"
}

function Show-Status {
    Log-Info "=== Millennium Scheduled Task Status ==="
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Write-Host "  Task Name   : $($task.TaskName)"
        Write-Host "  Path        : $($task.TaskPath)"
        Write-Host "  State       : $($task.State)"
        Write-Host "  Action      : $(($task.Actions | Select-Object -First 1).Execute) $(($task.Actions | Select-Object -First 1).Arguments)"
        $channelDisp = $Channel
        $actionArgs = "$(($task.Actions | Select-Object -First 1).Arguments)"
        if ($actionArgs -match '-Channel\s+(\S+)') {
            $channelDisp = $Matches[1]
        }
        $logFile = $updaterLog
        Write-Host ""
        Write-Host "=== Scheduler summary ==="
        Write-Host "  Channel     : $channelDisp"
        if (Test-Path -Path $logFile) {
            Write-Host "  Last log    : $logFile"
            Write-Host "  View logs   : millennium diag logs"
        } else {
            Write-Host "  Last log    : (none yet - runs after the first scheduled update)"
        }
        Write-Host "  Disable     : millennium schedule disable"
    } else {
        Write-Host "  Scheduled task is not registered."
        Write-Host ""
        Write-Host -ForegroundColor Yellow "Scheduler disabled. Enable with: millennium schedule enable [stable|beta|main]"
    }
}

function ConvertFrom-SecureStringPlain {
    param($SecureInput)
    if ($null -eq $SecureInput) {
        return ""
    }
    if ($SecureInput -is [string]) {
        return $SecureInput
    }
    if ($SecureInput -is [SecureString]) {
        if ($SecureInput.Length -eq 0) {
            return ""
        }
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureInput)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    return [string]$SecureInput
}

function Read-MaskedHost {
    param([string]$Prompt)
    [System.Console]::Error.Write($Prompt)
    try {
        $secure = Read-Host -AsSecureString
        return (ConvertFrom-SecureStringPlain -SecureInput $secure)
    } catch {
        # Fallback for mocked / non-console hosts
        return (Read-Host)
    }
}

function Run-Setup-Wizard {
    # Verify interactive console safely
    $keyAvailable = $false
    try {
        $keyAvailable = [System.Console]::KeyAvailable
    } catch {
        $keyAvailable = $false
    }
    if ($keyAvailable -eq $false -and $env:FORCE_WIZARD -ne "true") {
        # Check if stdin is piped
        try {
            $isPiped = [System.Console]::IsInputRedirected
        } catch {
            $isPiped = $false
        }
        if ($isPiped -and $env:FORCE_WIZARD -ne "true") {
            Log-Error "Error: Setup wizard must be run in an interactive terminal."
            exit 1
        }
    }

    Write-Host "`n=== Millennium Helpers Configuration Wizard ===" -ForegroundColor Blue
    Write-Host "This wizard will guide you through the configuration of the Millennium Helpers.`n"

    # 1. Release Channel Selection
    $defaultChNum = "1"
    $defaultChDesc = "Stable"
    $existingChannel = "stable"
    if (Test-Path -Path $configFile) {
        try {
            $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            if ($config -and $config.update_channel -eq "beta") {
                $defaultChNum = "2"
                $defaultChDesc = "Beta"
                $existingChannel = "beta"
            } elseif ($config -and $config.update_channel -eq "main") {
                $defaultChNum = "3"
                $defaultChDesc = "Main"
                $existingChannel = "main"
            }
        } catch {}
    }

    $channelVal = ""
    while ($true) {
        Write-Host "Choose Millennium Update Channel:"
        Write-Host "  1) Stable   — latest published release"
        Write-Host "  2) Beta     — beta-tagged prereleases"
        Write-Host "  3) Main     — tip-of-development prereleases"
        [System.Console]::Error.Write("Selection [1-3, default: $defaultChNum ($defaultChDesc)]: ")
        $chSel = Read-Host
        if ([string]::IsNullOrWhiteSpace($chSel)) {
            $chSel = $defaultChNum
        }
        if ($chSel -eq "1") {
            $channelVal = "stable"
            break
        } elseif ($chSel -eq "2") {
            $channelVal = "beta"
            break
        } elseif ($chSel -eq "3") {
            $channelVal = "main"
            break
        } else {
            Write-Host "Invalid selection. Please choose 1, 2, or 3." -ForegroundColor Red
        }
    }
    Write-Host "Selected channel: $channelVal`n"

    # 2. Automated Daily Update Scheduler Timer
    $defaultSched = "y"
    $defaultSchedDesc = "Y/n"
    $taskExists = $null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    if ($taskExists) {
        $defaultSched = "y"
        $defaultSchedDesc = "Y/n"
    } elseif (Test-Path -Path $configFile) {
        $defaultSched = "n"
        $defaultSchedDesc = "y/N"
    }

    $enableSched = ""
    while ($true) {
        [System.Console]::Error.Write("Would you like to enable the daily automated background update task? [$defaultSchedDesc]: ")
        $schedSel = Read-Host
        if ([string]::IsNullOrWhiteSpace($schedSel)) {
            $schedSel = $defaultSched
        }
        if ($schedSel -match "^[Yy]([Ee][Ss])?$") {
            $enableSched = "true"
            break
        } elseif ($schedSel -match "^[Nn]([Oo])?$") {
            $enableSched = "false"
            break
        } else {
            Write-Host "Invalid option. Please enter y or n." -ForegroundColor Red
        }
    }
    Write-Host "Automated task: $enableSched`n"

    # 3. GitHub API Token configuration
    $githubToken = ""
    $existingToken = $env:GITHUB_TOKEN
    if (Test-Path -Path $configFile) {
        try {
            $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            if ($config -and $config.github_token) {
                $existingToken = $config.github_token
            }
        } catch {}
    }

    Write-Host "To avoid GitHub API rate limits during updates, you can store an optional Personal Access Token (PAT)."
    if ($existingToken) {
        Write-Host "A PAT is already saved. Press Enter to keep it (it will not be cleared), or paste a new token to replace it." -ForegroundColor Yellow
        $githubToken = Read-MaskedHost -Prompt "GitHub PAT [keep existing]: "
        if ([string]::IsNullOrWhiteSpace($githubToken)) {
            $githubToken = $existingToken
            Write-Host "Kept existing GitHub PAT (unchanged).`n"
        } else {
            Write-Host "New GitHub PAT saved (hidden).`n"
        }
    } else {
        Write-Host "No PAT is configured yet. Press Enter to skip, or paste a token to save one." -ForegroundColor Yellow
        $githubToken = Read-MaskedHost -Prompt "GitHub PAT [optional]: "        if (-not [string]::IsNullOrWhiteSpace($githubToken)) {
            Write-Host "GitHub PAT saved (hidden).`n"
        } else {
            Write-Host "No GitHub PAT saved.`n"
        }
    }

    # Write configuration to LocalAppData config folder (preserve backup_* and other keys)
    if (!$global:DryRun) {
        if (!(Test-Path -Path $configDir)) {
            New-Item -ItemType Directory -Force -Path $configDir | Out-Null
        }
        $configObj = @{}
        if (Test-Path -Path $configFile) {
            try {
                $existing = Get-Content -Path $configFile -Raw | ConvertFrom-Json
                if ($existing) {
                    foreach ($p in $existing.PSObject.Properties) {
                        $configObj[$p.Name] = $p.Value
                    }
                }
            } catch {}
        }
        $configObj["update_channel"] = $channelVal
        $configObj["github_token"] = $githubToken
        $configObj | ConvertTo-Json | Set-Content -Path $configFile -Force
        Protect-HelpersConfigFile -Path $configFile
        Write-Host "`nConfiguration saved successfully to: $configFile" -ForegroundColor Green
    } else {
        Write-Host "`n[DRY RUN] Would write config to $($configFile):" -ForegroundColor Yellow
        Write-Host "  update_channel : $channelVal"
        if ($githubToken) {
            Write-Host "  github_token   : [set]"
        } else {
            Write-Host "  github_token   : (not set)"
        }
        Write-Host "  (other keys such as backup_limit are preserved)"
    }

    # Trigger Scheduled Task enablement if chosen
    if ($enableSched -eq "true") {
        Write-Host "`nConfiguring background update scheduled task..." -ForegroundColor Blue
        Enable-Task $channelVal
    }

    Write-Host "`nTip: tune backup retention anytime with:" -ForegroundColor Blue
    Write-Host "  millennium-schedule config set backup_limit 5"
    Write-Host "  millennium-schedule config set backup_max_age_days 30"
}

function Manage-Config {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [AllowEmptyCollection()]
        [string[]]$ConfigArgs = @()
    )
    $parts = @($ConfigArgs)
    $action = $null
    $key = $null
    $val = $null
    if ($parts.Count -gt 0) { $action = [string]$parts[0] }
    if ($parts.Count -gt 1) { $key = [string]$parts[1] }
    if ($parts.Count -gt 2) { $val = [string]$parts[2] }

    if ([string]::IsNullOrWhiteSpace($action) -or $action -eq "list") {
        Write-Host "=== Millennium Helpers Configuration ==="
        $data = $null
        if (Test-Path -Path $configFile) {
            try {
                $data = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            } catch {}
        }
        $keys = @("update_channel", "github_token", "backup_limit", "backup_max_age_days")
        foreach ($k in $keys) {
            $value = $null
            if ($data -and $data.PSObject.Properties[$k]) {
                $value = $data.$k
            }
            $valStr = ""
            if ($k -eq "github_token" -and $value) {
                $valStr = if ($value.Length -ge 4) { $value.Substring(0, 4) + ("*" * 8) } else { "*" * 8 }
            } elseif ($null -eq $value -or $value -eq "") {
                $valStr = "(not set)"
                if ($k -eq "update_channel") { $valStr = "stable (default)" }
                elseif ($k -eq "backup_limit") { $valStr = "5 (default)" }
            } else {
                $valStr = $value.ToString()
            }
            Write-Host "  $($k.PadRight(20)) : $valStr"
        }
        return
    }

    if ($action -eq "get") {
        if (!$key) {
            Log-Error "Error: config get requires a key name."
            exit 1
        }
        if ($key -ne "update_channel" -and $key -ne "github_token" -and $key -ne "backup_limit" -and $key -ne "backup_max_age_days") {
            Log-Error "Error: Invalid config key '$key'."
            exit 1
        }
        if (Test-Path -Path $configFile) {
            try {
                $data = Get-Content -Path $configFile -Raw | ConvertFrom-Json
                if ($data -and $data.PSObject.Properties[$key] -and $null -ne $data.$key) {
                    Write-Output $data.$key
                }
            } catch {}
        }
        return
    }

    if ($action -eq "set") {
        if (!$key) {
            Log-Error "Error: config set requires a key name."
            exit 1
        }
        if ($key -ne "update_channel" -and $key -ne "github_token" -and $key -ne "backup_limit" -and $key -ne "backup_max_age_days") {
            Log-Error "Error: Invalid config key '$key'."
            exit 1
        }

        # Validate values
        if ($key -eq "update_channel" -and $val -ne "stable" -and $val -ne "beta" -and $val -ne "main") {
            Log-Error "Error: update_channel must be 'stable', 'beta', or 'main'."
            exit 1
        }
        if ($key -eq "backup_limit") {
            if ($val -notmatch "^\d+$" -or [int]$val -lt 1) {
                Log-Error "Error: backup_limit must be a positive integer >= 1."
                exit 1
            }
        }
        if ($key -eq "backup_max_age_days" -and $val -and $val -notmatch "^\d+$") {
            Log-Error "Error: backup_max_age_days must be an integer."
            exit 1
        }

        if ($global:DryRun) {
            Log-Warn "[DRY RUN] Would set config option $key to $val"
        } else {
            $data = @{}
            if (Test-Path -Path $configFile) {
                try {
                    $data = Get-Content -Path $configFile -Raw | ConvertFrom-Json | ForEach-Object {
                        # Convert PSObject to hash table
                        $hash = @{}
                        foreach ($p in $_.PSObject.Properties) {
                            $hash[$p.Name] = $p.Value
                        }
                        $hash
                    }
                } catch {}
            }
            if ($key -eq "backup_limit" -or $key -eq "backup_max_age_days") {
                $data[$key] = if ([string]::IsNullOrEmpty($val)) { $null } else { [int]$val }
            } else {
                $data[$key] = $val
            }

            if (!(Test-Path -Path $configDir)) {
                New-Item -ItemType Directory -Force -Path $configDir | Out-Null
            }
            $data | ConvertTo-Json | Set-Content -Path $configFile -Force
            Protect-HelpersConfigFile -Path $configFile
            Log-Info "Config option $key set to '$val' successfully."
        }
        return
    }

    Log-Error "Error: Unknown config action '$action'."
    exit 1
}

# --- Dispatcher ---

switch ($Command) {
    "enable" {
        Enable-Task $Channel
    }
    "disable" {
        Disable-Task
    }
    "status" {
        Show-Status
    }
    "setup" {
        Run-Setup-Wizard
    }
    "config" {
        Manage-Config -ConfigArgs ([string[]]@($script:PositionalArgs))
    }
    Default {
        if ($Command) {
            Log-Error "Unknown command: $Command"
            $suggestion = Get-ClosestToken -InputToken $Command -Candidates @("enable", "disable", "status", "setup", "config")
            if ($suggestion) {
                Write-Host "Did you mean '$suggestion'?"
            }
            Write-Host "Try 'millennium-schedule -Help' for usage."
        } else {
            Show-Help
        }
        exit 1
    }
}
exit 0
