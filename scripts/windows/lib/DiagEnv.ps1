# DiagEnv.ps1 — Permissions, skins directory, scheduled task, and obsolete file checks
#
# Populates (no console output — printing is handled by Write-DiagReport):
#   $script:PermissionsOk      bool
#   $script:UnwritableDirs     string[]
#   $script:SkinsDirOk         bool
#   $script:TaskOk             bool
#   $script:TaskState          string
#   $script:CleanOfObsolete    bool
#   $script:ObsoleteFilesFound string[]

$script:PermissionsOk      = $true
$script:UnwritableDirs     = @()
$script:SkinsDirOk         = $true
$script:TaskOk             = $false
$script:TaskState          = ''
$script:CleanOfObsolete    = $true
$script:ObsoleteFilesFound = @()

function Test-FolderWrite {
    param([string]$Path)
    if (!(Test-Path -Path $Path)) { return $true }
    try {
        $testFile = Join-Path -Path $Path -ChildPath 'permissions_test.txt'
        New-Item -ItemType File -Path $testFile -Force | Out-Null
        Remove-Item -Path $testFile -Force | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-DiagPermissionsStatus {
    $script:PermissionsOk  = $true
    $script:UnwritableDirs = @()

    if ($env:DIAG_TEST_BYPASS_CHECKS -eq 'true') { return }

    if (!(Test-FolderWrite -Path $script:SteamPath)) {
        $script:PermissionsOk  = $false
        $script:UnwritableDirs += $script:SteamPath
    }
    if (!(Test-FolderWrite -Path $script:SkinsDir)) {
        $script:PermissionsOk  = $false
        $script:UnwritableDirs += $script:SkinsDir
    }
}

function Get-DiagSkinsDirStatus {
    $script:SkinsDirOk = $true

    if ($env:DIAG_TEST_BYPASS_CHECKS -eq 'true') { return }

    if (!(Test-Path -Path $script:SkinsDir)) {
        $script:SkinsDirOk = $false
    }
}

function Get-DiagTaskStatus {
    $script:TaskOk    = $false
    $script:TaskState = ''

    if ($env:DIAG_TEST_BYPASS_CHECKS -eq 'true') {
        $script:TaskOk    = $true
        $script:TaskState = 'Ready'
        return
    }

    $task = Get-ScheduledTask -TaskName 'MillenniumUpdate' -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        $script:TaskOk    = $true
        $script:TaskState = $task.State.ToString()
    }
}

function Get-DiagObsoleteStatus {
    $script:CleanOfObsolete    = $true
    $script:ObsoleteFilesFound = @()

    $rawList = @()
    if ($env:DIAG_TEST_OBSOLETE_LIST) {
        $rawList = $env:DIAG_TEST_OBSOLETE_LIST -split ','
    } else {
        $rawList = @(
            (Join-Path -Path $script:SteamPath -ChildPath 'millennium-upgrade-stable.ps1'),
            (Join-Path -Path $script:SteamPath -ChildPath 'millennium-upgrade-beta.ps1')
        )
        # Leftover loader from pre-Diag.ps1 rename
        if ($script:ScriptDir) {
            $rawList += (Join-Path -Path $script:ScriptDir -ChildPath 'lib\DiagReport.ps1')
        }
    }

    foreach ($f in $rawList) {
        $f = $f.Trim()
        if ($f -ne '' -and (Test-Path -Path $f)) {
            $script:CleanOfObsolete     = $false
            $script:ObsoleteFilesFound += $f
        }
    }
}
