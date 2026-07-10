# DiagSteam.ps1 - Steam client status and Millennium binary integrity checks
#
# Populates (no console output - printing is handled by Write-DiagReport):
#   $script:SteamRunning   bool
#   $script:SteamPid       int|$null
#   $script:BinariesOk     bool
#   $script:BinariesStatus string

$script:SteamRunning   = $false
$script:SteamPid       = $null
$script:BinariesOk     = $true
$script:BinariesStatus = ''

function Get-DiagSteamStatus {
    $script:SteamRunning = $false
    $script:SteamPid     = $null

    if ($env:DIAG_TEST_BYPASS_CHECKS -eq 'true') { return }

    $proc = Get-Process -Name 'steam' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $proc) {
        $script:SteamRunning = $true
        $script:SteamPid     = $proc.Id
    }
}

function Get-DiagBinariesStatus {
    $script:BinariesOk     = $true
    $script:BinariesStatus = ''

    if ($env:DIAG_TEST_BYPASS_CHECKS -eq 'true') {
        $script:BinariesOk     = $true
        $script:BinariesStatus = 'Verified Healthy (bypass)'
        return
    }

    $versionStr = 'Not Installed'
    $installedVerFile = Join-Path -Path $script:MillenniumDir -ChildPath 'version.txt'
    if (Test-Path -Path $installedVerFile) {
        $versionStr = (Get-Content -Path $installedVerFile -Raw).Trim()
    }
    $script:VersionStr = $versionStr

    $coreFiles = @(
        $script:WsockDll,
        (Join-Path -Path $script:MillenniumDir -ChildPath 'lib\millennium.dll'),
        (Join-Path -Path $script:MillenniumDir -ChildPath 'lib\millennium.hhx64.dll'),
        (Join-Path -Path $script:MillenniumDir -ChildPath 'bin\millennium.crashhandler64.exe'),
        (Join-Path -Path $script:MillenniumDir -ChildPath 'bin\millennium.luavm64.exe')
    )

    $missingCore = $false
    foreach ($f in $coreFiles) {
        if (!(Test-Path -Path $f)) {
            $missingCore = $true
            $script:BinariesOk = $false
        }
    }

    if ($missingCore) {
        $script:BinariesStatus = 'Corrupted (missing core files)'
    } elseif ($versionStr -eq 'Not Installed') {
        $script:BinariesOk     = $false
        $script:BinariesStatus = 'Not Installed'
    } else {
        $script:BinariesStatus = "v$versionStr ($($script:Channel) channel) - Verified Healthy"
    }
}
