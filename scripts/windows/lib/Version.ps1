# Version.ps1 - Helpers version resolution and helper script path lookup

function Get-HelpersVersion {
    $candidates = @()
    $winDir = $script:MillenniumHelpersWinDir
    if (-not $winDir -and $PSScriptRoot) {
        # Fallback when Version.ps1 is sourced without common.ps1 (tests): lib/ -> windows/
        $winDir = Split-Path -Parent -Path $PSScriptRoot
    }
    if ($winDir) {
        $candidates += (Join-Path -Path $winDir -ChildPath "..\..\VERSION")
        $candidates += (Join-Path -Path $winDir -ChildPath "VERSION")
    }
    $candidates += (Join-Path -Path $env:LOCALAPPDATA -ChildPath "millennium-helpers\VERSION")

    foreach ($path in $candidates) {
        if ($path -and [System.IO.File]::Exists($path)) {
            $ver = (Get-Content -Path $path -Raw -ErrorAction SilentlyContinue)
            if ($null -ne $ver) {
                $ver = $ver.Trim()
                if ($ver) { return $ver }
            }
        }
    }

    $repoRoot = $null
    if ($winDir) {
        $repoRoot = (Resolve-Path -Path (Join-Path -Path $winDir -ChildPath "..\..") -ErrorAction SilentlyContinue)
    }
    if ($repoRoot -and [System.IO.Directory]::Exists((Join-Path -Path $repoRoot.Path -ChildPath ".git"))) {
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

function Resolve-HelperPath {
    param([string]$Name)
    $scriptDir = $script:MillenniumHelpersWinDir
    if (-not $scriptDir) {
        $scriptDir = Split-Path -Parent -Path $PSScriptRoot
    }
    $scriptPath = Join-Path -Path $scriptDir -ChildPath "$Name.ps1"
    if ([System.IO.File]::Exists($scriptPath)) {
        return $scriptPath
    }

    $exe = Get-Command -Name "$Name.ps1" -ErrorAction SilentlyContinue
    if ($exe) {
        return $exe.Source
    }

    return $Name
}
