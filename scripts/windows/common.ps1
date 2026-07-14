# Shared helpers for Millennium Helper PowerShell scripts
set-strictmode -version Latest

# Set the current thread culture to invariant to avoid locale-specific issues (e.g. decimal separators)
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture

# Text formatting colors (honors NO_COLOR / FORCE_COLOR / console TTY)
$script:IsConsoleHost = $false
try {
    $script:IsConsoleHost = [Environment]::UserInteractive -and $Host.Name -match 'ConsoleHost|Visual Studio Code Host'
} catch {
    $script:IsConsoleHost = $false
}

if ($env:NO_COLOR) {
    $RED = ""
    $GREEN = ""
    $YELLOW = ""
    $BLUE = ""
    $NC = ""
} elseif ($env:FORCE_COLOR -or $script:IsConsoleHost) {
    $RED = "`e[0;31m"
    $GREEN = "`e[0;32m"
    $YELLOW = "`e[0;33m"
    $BLUE = "`e[0;34m"
    $NC = "`e[0m" # No Color
} else {
    $RED = ""
    $GREEN = ""
    $YELLOW = ""
    $BLUE = ""
    $NC = ""
}

$global:DryRun = $false
$global:AssumeYes = $false
$global:Quiet = $false

function Test-MillenniumQuiet {
    return ($global:Quiet -eq $true) -or [bool]$env:MILLENNIUM_QUIET
}

# Apply GNU-style flags from unbound $args (e.g. --json, --yes) onto script switches.
# Target keys may include booleans (Json, Yes, …) and string values (Channel, File, Rollback).
function Apply-GnuStyleArgs {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$InputArgs,
        [hashtable]$Target
    )
    $remaining = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $InputArgs.Count; $i++) {
        $tok = $InputArgs[$i]
        switch -Regex ($tok) {
            '^--json$' { if ($Target.ContainsKey('Json')) { $Target['Json'] = $true } else { $remaining.Add($tok) } }
            '^(--dry-run|-d)$' { if ($Target.ContainsKey('DryRun')) { $Target['DryRun'] = $true } else { $remaining.Add($tok) } }
            '^(--yes|-y)$' { if ($Target.ContainsKey('Yes')) { $Target['Yes'] = $true } else { $remaining.Add($tok) } }
            '^(--quiet|-q)$' {
                if ($Target.ContainsKey('Quiet')) { $Target['Quiet'] = $true }
                $global:Quiet = $true
                $env:MILLENNIUM_QUIET = "1"
            }
            '^(--help|-h)$' { if ($Target.ContainsKey('Help')) { $Target['Help'] = $true } else { $remaining.Add($tok) } }
            '^(--version|-V)$' { if ($Target.ContainsKey('Version')) { $Target['Version'] = $true } else { $remaining.Add($tok) } }
            '^(--all|-a)$' { if ($Target.ContainsKey('All')) { $Target['All'] = $true } else { $remaining.Add($tok) } }
            '^(--force|-f)$' { if ($Target.ContainsKey('Force')) { $Target['Force'] = $true } else { $remaining.Add($tok) } }
            '^(--skip-theme|-s)$' { if ($Target.ContainsKey('SkipTheme')) { $Target['SkipTheme'] = $true } else { $remaining.Add($tok) } }
            '^--stable$' { if ($Target.ContainsKey('Channel')) { $Target['Channel'] = 'stable' } else { $remaining.Add($tok) } }
            '^--beta$' { if ($Target.ContainsKey('Channel')) { $Target['Channel'] = 'beta' } else { $remaining.Add($tok) } }
            '^--main$' { if ($Target.ContainsKey('Channel')) { $Target['Channel'] = 'main' } else { $remaining.Add($tok) } }
            '^(--channel|-c)$' {
                if ($Target.ContainsKey('Channel') -and ($i + 1) -lt $InputArgs.Count) {
                    $i++
                    $Target['Channel'] = $InputArgs[$i]
                } else {
                    $remaining.Add($tok)
                }
            }
            '^--file$' {
                if ($Target.ContainsKey('File') -and ($i + 1) -lt $InputArgs.Count) {
                    $i++
                    $Target['File'] = $InputArgs[$i]
                } else {
                    $remaining.Add($tok)
                }
            }
            '^(--rollback|-r)$' {
                if ($Target.ContainsKey('Rollback') -and ($i + 1) -lt $InputArgs.Count) {
                    $i++
                    $Target['Rollback'] = $InputArgs[$i]
                } else {
                    $remaining.Add($tok)
                }
            }
            default { $remaining.Add($tok) }
        }
    }
    return $remaining.ToArray()
}

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

# Install Project Millennium MIT notice next to client binaries.
# Docs: docs/licensing.md
# Upstream: https://github.com/SteamClientHomebrew/Millennium/blob/main/LICENSE.md
function Install-MillenniumLicense {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestDir
    )
    if (-not (Test-Path -Path $DestDir -PathType Container)) {
        Log-Warn "Cannot install Millennium LICENSE — missing directory: $DestDir"
        return
    }
    $dest = Join-Path -Path $DestDir -ChildPath "LICENSE"
    $candidates = @()
    if ($PSScriptRoot) {
        $candidates += (Join-Path -Path $PSScriptRoot -ChildPath "..\..\third_party\MILLENNIUM-LICENSE.md")
        $candidates += (Join-Path -Path $PSScriptRoot -ChildPath "MILLENNIUM-LICENSE.md")
        $candidates += (Join-Path -Path $PSScriptRoot -ChildPath "third_party\MILLENNIUM-LICENSE.md")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers\MILLENNIUM-LICENSE.md")
        $candidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers\third_party\MILLENNIUM-LICENSE.md")
    }
    if ($env:USERPROFILE) {
        $candidates += (Join-Path -Path $env:USERPROFILE -ChildPath ".millennium-helpers\bin\MILLENNIUM-LICENSE.md")
    }

    foreach ($src in $candidates) {
        if ($src -and (Test-Path -Path $src -PathType Leaf)) {
            try {
                Copy-Item -Path $src -Destination $dest -Force
                return
            } catch {}
        }
    }

    try {
        $url = "https://raw.githubusercontent.com/SteamClientHomebrew/Millennium/main/LICENSE.md"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        if ((Test-Path -Path $dest) -and ((Get-Item $dest).Length -gt 0)) {
            return
        }
    } catch {}

    $fallback = @"
MIT License

Copyright (c) 2026 Project Millennium

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@
    try {
        Set-Content -Path $dest -Value $fallback -Encoding utf8 -Force
    } catch {}
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

function Protect-HelpersConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path -Path $Path -PathType Leaf)) {
        return
    }

    $onWindows = $false
    try {
        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            $onWindows = $true
        } elseif (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue) {
            $onWindows = [bool]$IsWindows
        } elseif ($env:OS -eq 'Windows_NT') {
            $onWindows = $true
        }
    } catch {
        $onWindows = ($env:OS -eq 'Windows_NT')
    }
    if (-not $onWindows) {
        return
    }

    try {
        $acl = Get-Acl -Path $Path
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) {
            $null = $acl.RemoveAccessRule($rule)
        }
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser,
            'FullControl',
            'Allow'
        )
        $acl.AddAccessRule($accessRule)
        Set-Acl -Path $Path -AclObject $acl
    } catch {
        Log-Warn "Could not restrict ACL on ${Path}: $($_.Exception.Message)"
    }
}

# Extract a zip into DestinationPath, rejecting absolute paths and '..' (zip-slip).
function Expand-SafeArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    if (!(Test-Path -LiteralPath $Path)) {
        throw "Zip archive not found: $Path"
    }
    if (!(Test-Path -LiteralPath $DestinationPath)) {
        New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
    }
    $destFull = [System.IO.Path]::GetFullPath($DestinationPath)
    if (-not $destFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $destFull += [System.IO.Path]::DirectorySeparatorChar
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if ($name.StartsWith('/') -or ($name.Length -ge 2 -and $name[1] -eq ':')) {
                throw "Refusing zip member with unsafe path: $($entry.FullName)"
            }
            $parts = $name.Split('/')
            if ($parts | Where-Object { $_ -eq '..' }) {
                throw "Refusing zip member with path traversal: $($entry.FullName)"
            }
            $target = [System.IO.Path]::GetFullPath((Join-Path -Path $DestinationPath -ChildPath ($name -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
            if (-not $target.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase) -and
                $target.TrimEnd('\') -ne $destFull.TrimEnd('\')) {
                throw "Refusing zip member outside extract root: $($entry.FullName)"
            }
        }
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if ([string]::IsNullOrWhiteSpace($name) -or $name.EndsWith('/')) {
                $dirRel = $name.TrimEnd('/')
                if ($dirRel) {
                    $dirPath = Join-Path -Path $DestinationPath -ChildPath ($dirRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                    if (!(Test-Path -LiteralPath $dirPath)) {
                        New-Item -ItemType Directory -Force -Path $dirPath | Out-Null
                    }
                }
                continue
            }
            $outPath = Join-Path -Path $DestinationPath -ChildPath ($name -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $outDir = Split-Path -Parent -Path $outPath
            if (!(Test-Path -LiteralPath $outDir)) {
                New-Item -ItemType Directory -Force -Path $outDir | Out-Null
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $outPath, $true)
        }
    } finally {
        $zip.Dispose()
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
    if ($GithubToken -and ($Url -like "*github.com*" -or $Url -like "*githubusercontent.com*")) {
        $headers["Authorization"] = "token $GithubToken"
    }

    try {
        # Ensure parent folder exists
        $parent = Split-Path -Parent $Dest
        if ($parent -and !(Test-Path -Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }

        # Prefer streaming download with byte progress on interactive consoles.
        $useProgress = $script:IsConsoleHost -and -not (Test-MillenniumQuiet)
        if ($useProgress) {
            Write-Progress -Activity $Msg -Status "Starting..." -PercentComplete 0
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = "GET"
            $req.UserAgent = "millennium-helpers"
            if ($headers.ContainsKey("Authorization")) {
                $req.Headers["Authorization"] = $headers["Authorization"]
            }
            $resp = $req.GetResponse()
            $total = $resp.ContentLength
            $stream = $resp.GetResponseStream()
            $fs = [System.IO.File]::Create($Dest)
            $buffer = New-Object byte[] 81920
            $readTotal = [int64]0
            try {
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $fs.Write($buffer, 0, $read)
                    $readTotal += $read
                    if ($total -gt 0) {
                        $pct = [int](($readTotal * 100L) / $total)
                        Write-Progress -Activity $Msg -Status ("{0:N0} / {1:N0} bytes" -f $readTotal, $total) -PercentComplete $pct
                    } else {
                        Write-Progress -Activity $Msg -Status ("{0:N0} bytes" -f $readTotal) -PercentComplete -1
                    }
                }
            } finally {
                $fs.Dispose()
                $stream.Dispose()
                $resp.Dispose()
            }
            Write-Progress -Activity $Msg -Completed
        } else {
            if ($headers.Count -gt 0) {
                Invoke-WebRequest -Uri $Url -OutFile $Dest -Headers $headers -UseBasicParsing -ErrorAction Stop
            } else {
                Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
            }
        }

        Write-Host -ForegroundColor Green "OK"
        return $true
    } catch {
        Write-Progress -Activity $Msg -Completed -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor Red "FAIL"
        Log-Error $_.Exception.Message
        return $false
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

# Suggest the closest known token for typos.
# Scoring (higher wins): 4 = prefix/extension, 3 = substring, else shared leading
# chars; subsequence matches (e.g. lst->list) score 3 minus length gap (floor 2).
# Returns $null unless bestScore >= 2 (avoids weak one-char coincidences).
function Get-ClosestToken {
    param(
        [string]$InputToken,
        [string[]]$Candidates
    )
    if ([string]::IsNullOrEmpty($InputToken)) { return $null }
    $best = $null
    $bestScore = 0
    foreach ($c in $Candidates) {
        $score = 0
        if ($c -eq $InputToken) { return $c }
        if ($c.StartsWith($InputToken) -or $InputToken.StartsWith($c)) {
            $score = 4
        } elseif ($c.Contains($InputToken) -or $InputToken.Contains($c)) {
            $score = 3
        } else {
            # Count identical leading characters (e.g. "upg" vs "upgrade" -> 3).
            $i = 0
            while ($i -lt $c.Length -and $i -lt $InputToken.Length -and $c[$i] -eq $InputToken[$i]) {
                $i++
            }
            $score = $i
            # Subsequence: every input char appears in order in candidate (skip gaps).
            # Require Length -ge 2 so a lone letter does not match every command.
            if ($InputToken.Length -ge 2) {
                $ni = 0
                $hi = 0
                while ($ni -lt $InputToken.Length -and $hi -lt $c.Length) {
                    if ($InputToken[$ni] -eq $c[$hi]) { $ni++ }
                    $hi++
                }
                if ($ni -eq $InputToken.Length) {
                    # Prefer closer lengths: "lst"/"list" beats "lst"/"listall".
                    $lenDiff = [Math]::Abs($c.Length - $InputToken.Length)
                    $subScore = 3 - $lenDiff
                    if ($subScore -lt 2) { $subScore = 2 }
                    if ($subScore -gt $score) { $score = $subScore }
                }
            }
        }
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $c
        }
    }
    if ($bestScore -ge 2) { return $best }
    return $null
}

function Test-ValidUpdateChannel {
    param([string]$Channel)
    return ($Channel -eq 'stable' -or $Channel -eq 'beta' -or $Channel -eq 'main')
}

function Require-UpdateChannel {
    param(
        [string]$Channel,
        [string]$Default = 'stable'
    )
    if ([string]::IsNullOrWhiteSpace($Channel)) {
        $Channel = $Default
    }
    if (-not (Test-ValidUpdateChannel -Channel $Channel)) {
        throw "Invalid update channel '$Channel'. Must be 'stable', 'beta', or 'main'."
    }
    return $Channel
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
