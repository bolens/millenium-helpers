# ScheduleWizard.ps1 - Schedule helpers for millennium-schedule.ps1

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
