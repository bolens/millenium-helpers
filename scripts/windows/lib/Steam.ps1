# Steam.ps1 - Steam path resolution and client lifecycle helpers


function Resolve-SteamPath {
    $regHKCU = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
    Write-DebugMsg "regHKCU is: '$regHKCU'"
    if ($regHKCU) {
        Write-DebugMsg "SteamPath is: '$($regHKCU.SteamPath)'"
    }
    if ($regHKCU -and $regHKCU.SteamPath) {
        $steamPath = $regHKCU.SteamPath
        $testRes = Test-Path -Path $steamPath
        Write-DebugMsg "Test-Path result: $testRes"
        if ($testRes) { return $steamPath }
    }

    # Check Local Machine registry (32-bit redirect)
    Write-DebugMsg "Reached HKLM32"
    $regHKLM32 = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
    if ($regHKLM32 -and $regHKLM32.InstallPath) {
        $steamPath = $regHKLM32.InstallPath
        if (Test-Path -Path $steamPath) { return $steamPath }
    }

    # Check Local Machine registry (64-bit native)
    Write-DebugMsg "Reached HKLM64"
    $regHKLM64 = Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -ErrorAction SilentlyContinue
    if ($regHKLM64 -and $regHKLM64.InstallPath) {
        $steamPath = $regHKLM64.InstallPath
        if (Test-Path -Path $steamPath) { return $steamPath }
    }

    # Fallback default locations
    Write-DebugMsg "Reached fallback paths"
    $fallbackPaths = @(
        "$env:ProgramFiles` (x86)`\Steam",
        "$env:ProgramFiles`\Steam",
        "C:\Steam"
    )
    foreach ($path in $fallbackPaths) {
        Write-DebugMsg "Test-Path checking fallback path: '$path'"
        if (Test-Path -Path $path) {
            return $path
        }
    }

    return $null
}


function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}


function Get-RunningGameProcess {
    $processes = Get-Process -ErrorAction SilentlyContinue
    foreach ($p in $processes) {
        try {
            $path = $p.Path
            if ($path -and ($path -like "*\steamapps\common\*")) {
                return $p
            }
        } catch {}
    }
    return $null
}


function Is-GameRunning {
    $game = Get-RunningGameProcess
    return $null -ne $game
}


function Get-RelaunchStateFile {
    $stateDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers"
    return Join-Path -Path $stateDir -ChildPath "relaunch_state.json"
}


function Capture-SteamEnv {
    $stateFile = Get-RelaunchStateFile
    $stateDir = Split-Path -Parent $stateFile

    # Check if steam is running and capture cmdline args
    $steamProc = Get-Process -Name "steam" -ErrorAction SilentlyContinue | Select-Object -First 1
    $steamArgs = ""
    $exePath = ""

    if ($null -ne $steamProc) {
        try {
            $exePath = $steamProc.Path
            # Attempt WMI query to retrieve launch arguments
            $wmiProc = Get-CimInstance Win32_Process -Filter "ProcessId = $($steamProc.Id)" -ErrorAction SilentlyContinue
            if ($wmiProc -and $wmiProc.CommandLine) {
                # CommandLine contains: "path/to/steam.exe" -args...
                # Remove executable prefix
                $cmdLine = $wmiProc.CommandLine.Trim()
                if ($cmdLine.StartsWith("`"")) {
                    $endQuote = $cmdLine.IndexOf("`"", 1)
                    if ($endQuote -gt 0) {
                        $steamArgs = $cmdLine.Substring($endQuote + 1).Trim()
                    }
                } else {
                    $spaceIdx = $cmdLine.IndexOf(" ")
                    if ($spaceIdx -gt 0) {
                        $steamArgs = $cmdLine.Substring($spaceIdx + 1).Trim()
                    }
                }
            }
        } catch {}
    }

    $state = @{
        "SteamRunning" = ($null -ne $steamProc);
        "Executable"   = $exePath;
        "Arguments"    = $steamArgs;
    }

    if ($global:DryRun) {
        Log-Warn "[DRY RUN] Would write relaunch state: $($state | ConvertTo-Json -Compress)"
    } else {
        if (!(Test-Path -Path $stateDir)) {
            New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        }
        $state | ConvertTo-Json | Set-Content -Path $stateFile -Force
    }
}


function Relaunch-Steam {
    $stateFile = Get-RelaunchStateFile
    if (!(Test-Path -Path $stateFile)) {
        Log-Info "No saved relaunch state found. Steam will not be restarted."
        return
    }

    try {
        $state = Get-Content -Path $stateFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -eq $state) {
            # Fallback to manual parsing if ConvertFrom-Json isn't working
            $state = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
        }
    } catch {
        Log-Error "Failed to parse relaunch state file."
        return
    } finally {
        if (!$global:DryRun -and (Test-Path -Path $stateFile)) {
            Remove-Item -Path $stateFile -Force
        }
    }

    if ($state -and $state.SteamRunning -and $state.Executable) {
        Log-Info "Relaunching Steam client: $($state.Executable) $($state.Arguments)"
        Execute-Cmd -ScriptBlock {
            Start-Process -FilePath $state.Executable -ArgumentList $state.Arguments
        } -Description "Start-Process `"$($state.Executable)`" `"$($state.Arguments)`""
    }
}

# Confirm before closing Steam when stdin is interactive.
# Non-interactive sessions, -Yes / $global:AssumeYes, scheduled jobs, and test suite skip the prompt.
# Returns $true on success, $false if the user declines.


function Confirm-CloseSteam {
    param(
        [switch]$Yes
    )

    $steamProc = Get-Process -Name "steam" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $steamProc) {
        return $true
    }

    $assumeYes = $false
    if ($Yes) { $assumeYes = $true }
    if ($global:AssumeYes) { $assumeYes = $true }
    if ($env:TEST_SUITE_RUN -or $env:PSTESTS) { $assumeYes = $true }

    $interactive = $false
    try {
        $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    } catch {
        $interactive = $false
    }

    if (-not $assumeYes -and $interactive) {
        Write-Host "${YELLOW}Steam is running and must be closed to continue.${NC}"
        $reply = Read-Host "Close Steam now? [y/N]"
        if ($reply -notmatch '^[Yy]([Ee][Ss])?$') {
            Log-Error "Aborted: Steam must be closed to continue. Re-run with -Yes to skip this prompt."
            return $false
        }
    }

    Close-SteamGracefully
    return $true
}


function Close-SteamGracefully {
    $steamProc = Get-Process -Name "steam" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $steamProc) {
        return
    }

    Log-Info "Closing Steam gracefully..."
    # On Windows, we can run steam.exe -shutdown to close it gracefully
    $steamPath = Resolve-SteamPath
    $steamExe = Join-Path -Path $steamPath -ChildPath "steam.exe"
    if (Test-Path -Path $steamExe) {
        Execute-Cmd -ScriptBlock {
            Start-Process -FilePath $steamExe -ArgumentList "-shutdown" -Wait
        } -Description "steam.exe -shutdown"
    } else {
        # Fallback to Stop-Process if launcher not found
        Execute-Cmd -ScriptBlock {
            Stop-Process -Name "steam" -Force
        } -Description "Stop-Process -Name steam -Force"
    }

    # Wait up to 10 seconds for it to close
    $timeout = 10
    while ((Get-Process -Name "steam" -ErrorAction SilentlyContinue) -and ($timeout -gt 0)) {
        Start-Sleep -Seconds 1
        $timeout--
    }
}
