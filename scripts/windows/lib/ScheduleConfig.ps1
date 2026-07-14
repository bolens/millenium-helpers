# ScheduleConfig.ps1 - Schedule helpers for millennium-schedule.ps1

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
