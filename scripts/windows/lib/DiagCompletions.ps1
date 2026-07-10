# DiagCompletions.ps1 - PowerShell completion file + profile-hook health
#
# Populates:
#   $script:CompletionsOk          bool
#   $script:CompletionFileMissing  bool
#   $script:CompletionHookMissing  bool
#   $script:CompletionFilePath     string (expected completer path, if known)

$script:CompletionsOk         = $true
$script:CompletionFileMissing = $false
$script:CompletionHookMissing = $false
$script:CompletionFilePath    = ''

function Get-DiagCompletionCandidates {
    $paths = [System.Collections.Generic.List[string]]::new()

    if ($script:ScriptDir) {
        $paths.Add((Join-Path -Path $script:ScriptDir -ChildPath 'millennium-helpers.completion.ps1'))
        # Scoop / release-zip / checkout: completions next to scripts\windows -> repo root
        $repoRoot = Split-Path -Parent (Split-Path -Parent $script:ScriptDir)
        if ($repoRoot) {
            $paths.Add((Join-Path -Path $repoRoot -ChildPath 'completions\powershell\millennium-helpers.ps1'))
        }
    }

    if ($env:USERPROFILE) {
        $paths.Add((Join-Path -Path $env:USERPROFILE -ChildPath '.millennium-helpers\bin\millennium-helpers.completion.ps1'))
    }

    return ($paths | Select-Object -Unique)
}

function Get-DiagProfilePaths {
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if (-not $userHome) { return @() }
    $profiles = @(
        (Join-Path -Path $userHome -ChildPath 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path -Path $userHome -ChildPath 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    )
    if ($PROFILE -and $PROFILE.StartsWith($userHome)) {
        $profiles = @($PROFILE) + $profiles
    }
    return ($profiles | Select-Object -Unique)
}

function Test-DiagCompletionHookPresent {
    param([string]$CompletionPath)
    foreach ($profilePath in (Get-DiagProfilePaths)) {
        if (!(Test-Path -Path $profilePath)) { continue }
        $content = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        if ($content -like '*millennium-helpers.completion.ps1*' -or
            $content -like '*completions*powershell*millennium-helpers.ps1*' -or
            ($CompletionPath -and $content -like "*$([IO.Path]::GetFileName($CompletionPath))*")) {
            return $true
        }
    }
    return $false
}

function Get-DiagCompletionsStatus {
    $script:CompletionsOk         = $true
    $script:CompletionFileMissing = $false
    $script:CompletionHookMissing = $false
    $script:CompletionFilePath    = ''

    if ($env:DIAG_TEST_BYPASS_CHECKS -eq 'true') {
        if ($env:DIAG_TEST_COMPLETIONS_OK -eq 'false') {
            $script:CompletionsOk         = $false
            $script:CompletionFileMissing = $true
            $script:CompletionHookMissing = $true
        }
        return
    }

    if ($env:DIAG_TEST_COMPLETIONS_OK -eq 'false') {
        $script:CompletionsOk         = $false
        $script:CompletionFileMissing = $true
        $script:CompletionHookMissing = $true
        return
    }

    $found = $null
    foreach ($candidate in (Get-DiagCompletionCandidates)) {
        if ($candidate -and (Test-Path -Path $candidate -PathType Leaf)) {
            $found = $candidate
            break
        }
    }

    if (-not $found) {
        $script:CompletionsOk         = $false
        $script:CompletionFileMissing = $true
        # Still record preferred dest for doctor restore
        if ($script:ScriptDir) {
            $script:CompletionFilePath = Join-Path -Path $script:ScriptDir -ChildPath 'millennium-helpers.completion.ps1'
        } elseif ($env:USERPROFILE) {
            $script:CompletionFilePath = Join-Path -Path $env:USERPROFILE -ChildPath '.millennium-helpers\bin\millennium-helpers.completion.ps1'
        }
        return
    }

    $script:CompletionFilePath = $found

    if (!(Test-DiagCompletionHookPresent -CompletionPath $found)) {
        $script:CompletionsOk         = $false
        $script:CompletionHookMissing = $true
    }
}
