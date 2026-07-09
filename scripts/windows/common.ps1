# Shared helpers for Millennium Helper PowerShell scripts
set-strictmode -version Latest

# Text formatting colors
$RED = "`e[0;31m"
$GREEN = "`e[0;32m"
$YELLOW = "`e[0;33m"
$BLUE = "`e[0;34m"
$NC = "`e[0m" # No Color

$global:DryRun = $false

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

function Resolve-SteamPath {
    # Check Current User registry
    $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if ($steamPath -and (Test-Path -Path $steamPath)) {
        return $steamPath
    }

    # Check Local Machine registry (32-bit redirect)
    $steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    if ($steamPath -and (Test-Path -Path $steamPath)) {
        return $steamPath
    }

    # Check Local Machine registry (64-bit native)
    $steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    if ($steamPath -and (Test-Path -Path $steamPath)) {
        return $steamPath
    }

    # Fallback default locations
    $fallbackPaths = @(
        "$env:ProgramFiles` (x86)`\Steam",
        "$env:ProgramFiles`\Steam",
        "C:\Steam"
    )
    foreach ($path in $fallbackPaths) {
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
        $state = Get-Content -Path $stateFile | ConvertTo-Json -ErrorAction SilentlyContinue
        if ($null -eq $state) {
            # Fallback to manual parsing if ConvertTo-Json isn't working
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

function Download-File {
    param(
        [string]$Url,
        [string]$Dest,
        [string]$Msg = "Downloading",
        [string]$GithubToken = $null
    )

    if ($global:DryRun) {
        Log-Warn "[DRY RUN] Would download: $Url -> $Dest"
        return $true
    }

    Write-Host -NoNewline "$Msg... "

    $headers = @{}
    if ($GithubToken -and ($Url -like "*github.com*")) {
        $headers["Authorization"] = "token $GithubToken"
    }

    try {
        # Ensure parent folder exists
        $parent = Split-Path -Parent $Dest
        if ($parent -and !(Test-Path -Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }

        # Run web request
        if ($headers.Count -gt 0) {
            Invoke-WebRequest -Uri $Url -OutFile $Dest -Headers $headers -UseBasicParsing -ErrorAction Stop
        } else {
            Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
        }
        
        Write-Host -ForegroundColor Green "OK"
        return $true
    } catch {
        Write-Host -ForegroundColor Red "FAIL"
        Log-Error $_.Exception.Message
        return $false
    }
}

function Resolve-HelperPath {
    param([string]$Name)
    # Check scripts directory relative to common.ps1
    $scriptDir = $PSScriptRoot
    $scriptPath = Join-Path -Path $scriptDir -ChildPath "$Name.ps1"
    if (Test-Path -Path $scriptPath) {
        return $scriptPath
    }
    
    # Try system PATH
    $exe = Get-Command -Name "$Name.ps1" -ErrorAction SilentlyContinue
    if ($exe) {
        return $exe.Source
    }
    
    return $Name
}
