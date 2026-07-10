# Shared helpers for Millennium Helper PowerShell scripts
set-strictmode -version Latest

# Set the current thread culture to invariant to avoid locale-specific issues (e.g. decimal separators)
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture

# Text formatting colors (honors NO_COLOR)
if ($env:NO_COLOR) {
    $RED = ""
    $GREEN = ""
    $YELLOW = ""
    $BLUE = ""
    $NC = ""
} else {
    $RED = "`e[0;31m"
    $GREEN = "`e[0;32m"
    $YELLOW = "`e[0;33m"
    $BLUE = "`e[0;34m"
    $NC = "`e[0m" # No Color
}

$global:DryRun = $false

function Write-DebugMsg {
    param([string]$Msg)
    $debugEnabled = $env:MILLENNIUM_DEBUG -or ($VerbosePreference -eq 'Continue')
    if ($debugEnabled) {
        Write-Host "DEBUG: $Msg"
    }
}

function Get-HelpersVersion {
    $candidates = @()
    if ($PSScriptRoot) {
        $candidates += (Join-Path -Path $PSScriptRoot -ChildPath "..\..\VERSION")
        $candidates += (Join-Path -Path $PSScriptRoot -ChildPath "VERSION")
    }
    $candidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers\VERSION")

    foreach ($path in $candidates) {
        if ($path -and (Test-Path -Path $path -PathType Leaf)) {
            $ver = (Get-Content -Path $path -Raw -ErrorAction SilentlyContinue).Trim()
            if ($ver) { return $ver }
        }
    }

    $repoRoot = $null
    if ($PSScriptRoot) {
        $repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\..") -ErrorAction SilentlyContinue)
    }
    if ($repoRoot -and (Test-Path -Path (Join-Path -Path $repoRoot -ChildPath ".git"))) {
        try {
            $gitVer = (& git -C $repoRoot.Path describe --tags --always --dirty 2>$null)
            if ($gitVer) { return ($gitVer -replace '^v', '') }
        } catch {}
    }

    return "unknown"
}

function Write-HelpersVersion {
    param([string]$Name = "millennium-helpers")
    Write-Output "$Name $(Get-HelpersVersion)"
}

if (!$env:LOCALAPPDATA) {
    $env:LOCALAPPDATA = Join-Path -Path $env:HOME -ChildPath ".config"
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
