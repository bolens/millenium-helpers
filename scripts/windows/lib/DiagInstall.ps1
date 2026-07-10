# DiagInstall.ps1 - Install method detection (scoop / winget / manual / mixed / none)
#
# Populates:
#   $script:InstallMethod      string   scoop|winget|manual|mixed|none
#   $script:MixedInstallOk     bool     false when mixed
#   $script:HelpersCheckout    string   path to local dev checkout (or '')
#   $script:LatestReleaseTag   string   set later by Get-LatestReleaseTag
#   $script:LatestReleaseVersion string set later by Get-LatestReleaseTag

$script:InstallMethod       = ''
$script:MixedInstallOk      = $true
$script:HelpersCheckout     = ''
$script:LatestReleaseTag    = ''
$script:LatestReleaseVersion = ''
$script:HelpersTrack        = ''
$script:HelpersTrackRef     = ''
$script:IsScoopGit          = $false
$script:IsWingetGit         = $false

function Find-HelpersCheckout {
    if ($env:DIAG_TEST_CHECKOUT) {
        $script:HelpersCheckout = $env:DIAG_TEST_CHECKOUT
        return
    }

    $script:HelpersCheckout = ''

    $candidates = [System.Collections.Generic.List[string]]::new()

    # Two levels up from the lib dir (lib -> windows -> scripts -> repo root)
    if ($script:DiagLibDir) {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $script:DiagLibDir)
        if ($repoRoot) { $candidates.Add($repoRoot) }
    }

    $userProfile = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    foreach ($suffix in @('dev\millenium-helpers', 'millenium-helpers', 'src\millenium-helpers')) {
        $candidates.Add((Join-Path -Path $userProfile -ChildPath $suffix))
    }

    foreach ($candidate in $candidates) {
        if (!$candidate) { continue }
        # Packaging checkout marker (Linux-style)
        if (Test-Path -Path (Join-Path -Path $candidate -ChildPath 'packaging\millennium-helpers-git\PKGBUILD')) {
            $script:HelpersCheckout = $candidate
            return
        }
        if (Test-Path -Path (Join-Path -Path $candidate -ChildPath 'packaging\millennium-helpers\PKGBUILD')) {
            $script:HelpersCheckout = $candidate
            return
        }
        # Windows dev checkout marker: VERSION + scripts\windows
        if ((Test-Path -Path (Join-Path -Path $candidate -ChildPath 'VERSION')) -and
            (Test-Path -Path (Join-Path -Path $candidate -ChildPath 'scripts\windows'))) {
            $script:HelpersCheckout = $candidate
            return
        }
    }
}

function Test-HelpersScoopPackaged {
    if ($env:DIAG_TEST_SCOOP_PACKAGED -eq 'true') { return $true }
    if ($PSCommandPath -and $PSCommandPath -like '*\scoop\apps\*') { return $true }
    try {
        $scoopOut = & scoop which millennium 2>&1
        if ($LASTEXITCODE -eq 0) { return $true }
    } catch { }
    return $false
}

function Test-HelpersWingetPackaged {
    if ($env:DIAG_TEST_WINGET_PACKAGED -eq 'true') { return $true }
    if ($PSCommandPath -and $PSCommandPath -like '*\AppData\Local\Packages\*') { return $true }
    if ($PSCommandPath -and $PSCommandPath -like '*\WinGet\Packages\*') { return $true }
    return $false
}

function Test-HelpersManualInstalled {
    if (-not $env:USERPROFILE) { return $false }
    $manualBin = Join-Path -Path $env:USERPROFILE -ChildPath '.millennium-helpers\bin'
    return (Test-Path -Path (Join-Path -Path $manualBin -ChildPath 'millennium-diag.ps1'))
}

function Test-HelpersScoopGit {
    if ($env:DIAG_TEST_SCOOP_GIT -eq 'true') { return $true }
    try {
        $info = & scoop list millennium-helpers-git 2>&1
        if ($LASTEXITCODE -eq 0 -and "$info" -match 'millennium-helpers-git') { return $true }
    } catch { }
    if ($PSCommandPath -and $PSCommandPath -like '*\scoop\apps\millennium-helpers-git\*') { return $true }
    return $false
}

function Test-HelpersWingetGit {
    if ($env:DIAG_TEST_WINGET_GIT -eq 'true') { return $true }
    if ($PSCommandPath -and $PSCommandPath -like '*millenniumhelpers.git*') { return $true }
    if ($PSCommandPath -and $PSCommandPath -like '*millenniumhelpers+git*') { return $true }
    return $false
}

function Ensure-HelpersTrackMeta {
    if ($env:DIAG_TEST_HELPERS_TRACK) {
        $script:HelpersTrack = $env:DIAG_TEST_HELPERS_TRACK
        $script:HelpersTrackRef = if ($env:DIAG_TEST_HELPERS_REF) { $env:DIAG_TEST_HELPERS_REF } else { '' }
        return
    }

    $userProfile = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if (-not $userProfile) {
        if ($script:IsScoopGit -or $script:IsWingetGit) {
            $script:HelpersTrack = 'main'
            $script:HelpersTrackRef = 'main'
        } else {
            $script:HelpersTrack = 'release'
            $script:HelpersTrackRef = 'latest'
        }
        return
    }

    $installRoot = Join-Path $userProfile '.millennium-helpers'
    $trackLib = if ($script:DiagLibDir) { Join-Path $script:DiagLibDir 'InstallTrack.ps1' } else { '' }
    if ($trackLib -and (Test-Path -LiteralPath $trackLib)) {
        . $trackLib
        $method = 'manual'
        if ($script:IsScoopGit) { $method = 'scoop-git' }
        elseif ($script:IsWingetGit) { $method = 'winget-git' }
        elseif ($script:InstallMethod -eq 'scoop' -or $script:InstallMethod -eq 'winget') { $method = $script:InstallMethod }
        elseif ($script:HelpersCheckout) { $method = 'checkout' }
        [void](Migrate-HelpersInstallMetaIfNeeded -InstallRoot $installRoot -Method $method -Checkout $script:HelpersCheckout)
        $meta = Read-HelpersInstallMeta -InstallRoot $installRoot
        if ($meta) {
            $script:HelpersTrack = [string]$meta.track
            $script:HelpersTrackRef = [string]$meta.ref
            return
        }
    }

    if ($script:IsScoopGit -or $script:IsWingetGit) {
        $script:HelpersTrack = 'main'
        $script:HelpersTrackRef = 'main'
    } else {
        $script:HelpersTrack = 'release'
        $script:HelpersTrackRef = 'latest'
    }
}

function Get-DiagInstallMethod {
    if ($env:DIAG_TEST_INSTALL_METHOD) {
        $script:InstallMethod  = $env:DIAG_TEST_INSTALL_METHOD
        $script:MixedInstallOk = ($script:InstallMethod -ne 'mixed')
        Find-HelpersCheckout
        return
    }

    $scoopOk  = Test-HelpersScoopPackaged
    $wingetOk = Test-HelpersWingetPackaged
    $manualOk = Test-HelpersManualInstalled
    $script:IsScoopGit = Test-HelpersScoopGit
    $script:IsWingetGit = Test-HelpersWingetGit

    $count = 0
    if ($scoopOk)  { $count++ }
    if ($wingetOk) { $count++ }
    if ($manualOk) { $count++ }

    if ($count -gt 1) {
        $script:InstallMethod  = 'mixed'
        $script:MixedInstallOk = $false
    } elseif ($scoopOk) {
        $script:InstallMethod  = 'scoop'
        $script:MixedInstallOk = $true
    } elseif ($wingetOk) {
        $script:InstallMethod  = 'winget'
        $script:MixedInstallOk = $true
    } elseif ($manualOk) {
        $script:InstallMethod  = 'manual'
        $script:MixedInstallOk = $true
    } else {
        $script:InstallMethod  = 'none'
        $script:MixedInstallOk = $true
    }

    Find-HelpersCheckout
    Ensure-HelpersTrackMeta
}

function Show-DiagInstallMethod {
    Write-Host "`nHelper Scripts Install Method:"
    switch ($script:InstallMethod) {
        'scoop' {
            if ($script:IsScoopGit) {
                Print-DiagItem -Status 'ok' -Label 'Install method' -Value 'Scoop package (millennium-helpers-git)'
            } else {
                Print-DiagItem -Status 'ok' -Label 'Install method' -Value 'Scoop package (millennium-helpers)'
            }
        }
        'winget' {
            if ($script:IsWingetGit) {
                Print-DiagItem -Status 'ok' -Label 'Install method' -Value 'Winget package (bolens.millenniumhelpers.git)'
            } else {
                Print-DiagItem -Status 'ok' -Label 'Install method' -Value 'Winget package (bolens.millenniumhelpers)'
            }
        }
        'manual' { Print-DiagItem -Status 'ok'    -Label 'Install method' -Value 'Manual install (install.ps1)' }
        'mixed'  { Print-DiagItem -Status 'error' -Label 'Install method' -Value 'Mixed installs detected (scoop/winget/manual)' }
        'none'   { Print-DiagItem -Status 'warn'  -Label 'Install method' -Value 'No helper scripts detected' }
        default  { Print-DiagItem -Status 'warn'  -Label 'Install method' -Value "Unknown ($($script:InstallMethod))" }
    }
    if ($script:HelpersTrack) {
        $refSuffix = if ($script:HelpersTrackRef) { " ($($script:HelpersTrackRef))" } else { '' }
        Print-DiagItem -Status 'ok' -Label 'Helpers track' -Value "$($script:HelpersTrack)$refSuffix"
    }
    if ($script:HelpersCheckout) {
        Print-DiagItem -Status 'ok' -Label 'Local checkout' -Value $script:HelpersCheckout
    }
}
