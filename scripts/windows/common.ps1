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

if (!$env:LOCALAPPDATA) {
    $env:LOCALAPPDATA = Join-Path -Path $env:HOME -ChildPath ".config"
}

# Source shared modules (order: logging before license; argv/steam after logging)
# Capture install root at load time: $PSScriptRoot at call-time may be the caller
# (e.g. Pester), not scripts/windows.
$script:MillenniumHelpersWinDir = $PSScriptRoot
$_CommonLibDir = Join-Path -Path $script:MillenniumHelpersWinDir -ChildPath 'lib'
foreach ($_mod in @(
        'Logging.ps1',
        'Args.ps1',
        'Version.ps1',
        'Steam.ps1',
        'Archive.ps1',
        'Download.ps1',
        'Config.ps1',
        'License.ps1',
        'InstallTrack.ps1'
    )) {
    $_modPath = Join-Path -Path $_CommonLibDir -ChildPath $_mod
    # Use .NET Exists so Pester Test-Path mocks cannot block module loading.
    if ([System.IO.File]::Exists($_modPath)) {
        . $_modPath
    } else {
        throw "Shared module not found: $_modPath"
    }
}
Remove-Variable _CommonLibDir, _mod, _modPath -ErrorAction SilentlyContinue
