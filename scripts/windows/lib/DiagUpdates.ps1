# DiagUpdates.ps1 - Helper script update checks against latest GitHub release
#
# Populates (no console output - printing done in Write-DiagReport):
#   $script:ScriptsUpToDate  bool
#   $script:OutOfDateScripts string[]

$script:ScriptsUpToDate  = $true
$script:OutOfDateScripts = @()

# Relative paths inside the release zip that are checked for manual installs
$script:KeyScripts = @(
    'scripts\windows\millennium-diag.ps1',
    'scripts\windows\common.ps1',
    'scripts\windows\millennium-upgrade.ps1',
    'scripts\windows\millennium-schedule.ps1',
    'scripts\windows\millennium-repair.ps1',
    'scripts\windows\millennium-theme.ps1',
    'scripts\windows\millennium-purge.ps1',
    'scripts\windows\millennium.ps1'
)

function Test-GitHubReachable {
    try {
        $null = Invoke-WebRequest -Uri 'https://github.com' `
            -UseBasicParsing -TimeoutSec 3 -MaximumRedirection 2 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-HelperScriptsUpToDate {
    $script:ScriptsUpToDate  = $true
    $script:OutOfDateScripts = @()

    if ($env:DIAG_TEST_BYPASS_CHECKS -eq 'true') { return }

    if (!(Test-GitHubReachable)) {
        # Offline: leave as up-to-date (can't determine otherwise)
        return
    }

    if (!$script:LatestReleaseTag) { Get-LatestReleaseTag }
    if (!$script:InstallMethod)    { Get-DiagInstallMethod }

    switch ($script:InstallMethod) {
        { $_ -in @('scoop', 'winget') } {
            try { $installedVer = Get-HelpersVersion } catch { $installedVer = 'unknown' }
            if ($script:IsScoopGit -or $script:IsWingetGit -or $script:HelpersTrack -eq 'main') {
                # Tip-of-main packages are not compared to release tags.
                return
            }
            if ($script:LatestReleaseVersion -and $installedVer -and $installedVer -ne 'unknown') {
                if ($installedVer -ne $script:LatestReleaseVersion) {
                    $script:ScriptsUpToDate = $false
                    $script:OutOfDateScripts += 'millennium-helpers'
                }
            }
            return
        }
        'mixed' {
            $script:ScriptsUpToDate = $false
            return
        }
        'none' {
            $script:ScriptsUpToDate = $false
            return
        }
    }

    if ($script:HelpersTrack -eq 'checkout') {
        return
    }

    # Manual install: compare key scripts via SHA256 against track archive
    if (-not $env:USERPROFILE) { return }
    if (!(Get-ReleaseZipExtract)) {
        return
    }

    $binDir = Join-Path -Path $env:USERPROFILE -ChildPath '.millennium-helpers\bin'

    foreach ($relPath in $script:KeyScripts) {
        $scriptName  = Split-Path -Leaf $relPath
        $localPath   = Join-Path -Path $binDir -ChildPath $scriptName
        $releasePath = Get-ReleaseSourcePath -RelativePath $relPath

        if (!$releasePath) { continue }

        if (Test-Path -Path $localPath) {
            $localHash   = (Get-FileHash -Path $localPath   -Algorithm SHA256).Hash
            $releaseHash = (Get-FileHash -Path $releasePath -Algorithm SHA256).Hash
            if ($localHash -ne $releaseHash) {
                $script:ScriptsUpToDate  = $false
                $script:OutOfDateScripts += $scriptName
            }
        } else {
            $script:ScriptsUpToDate  = $false
            $script:OutOfDateScripts += $scriptName
        }
    }
}
