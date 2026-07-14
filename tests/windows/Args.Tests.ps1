# Pester tests for scripts/windows/lib/Args.ps1 (via common.ps1)
Describe 'Args module' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $winScriptDir = Join-Path $repoRoot 'scripts\windows'
        . (Join-Path -Path $winScriptDir -ChildPath 'common.ps1')
    }

    AfterAll {
        $global:Quiet = $false
        Remove-Item Env:MILLENNIUM_QUIET -ErrorAction SilentlyContinue
    }

    It 'Get-ClosestToken prefers prefix matches' {
        Get-ClosestToken -InputToken 'enab' -Candidates @('enable', 'disable', 'status') | Should -Be 'enable'
    }

    It 'Get-ClosestToken returns null for weak matches' {
        Get-ClosestToken -InputToken 'z' -Candidates @('enable', 'disable') | Should -Be $null
    }

    It 'Get-ClosestToken handles subsequence typos' {
        Get-ClosestToken -InputToken 'lst' -Candidates @('list', 'install', 'status') | Should -Be 'list'
    }

    It 'Apply-GnuStyleArgs sets Yes and Quiet' {
        $target = @{ Yes = $false; Quiet = $false; DryRun = $false }
        try {
            $remaining = @(Apply-GnuStyleArgs -InputArgs @('--yes', '--quiet', 'leftover') -Target $target)
            $target['Yes'] | Should -Be $true
            $target['Quiet'] | Should -Be $true
            $remaining | Should -Be @('leftover')
        } finally {
            $global:Quiet = $false
            Remove-Item Env:MILLENNIUM_QUIET -ErrorAction SilentlyContinue
        }
    }

    It 'Test-ValidUpdateChannel accepts stable beta main' {
        Test-ValidUpdateChannel -Channel 'stable' | Should -Be $true
        Test-ValidUpdateChannel -Channel 'beta' | Should -Be $true
        Test-ValidUpdateChannel -Channel 'main' | Should -Be $true
        Test-ValidUpdateChannel -Channel 'nightly' | Should -Be $false
    }

    It 'Require-UpdateChannel throws on invalid channel' {
        { Require-UpdateChannel -Channel 'nightly' } | Should -Throw
    }
}
