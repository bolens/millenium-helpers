# Pester tests for scripts/windows/lib/Dispatcher.ps1
Describe 'Dispatcher module' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $winScriptDir = Join-Path $repoRoot 'scripts\windows'
        $ScriptDir = $winScriptDir
        . (Join-Path -Path $winScriptDir -ChildPath 'lib\Dispatcher.ps1')
    }

    It 'Get-CommandSuggestion exact match' {
        Get-CommandSuggestion -InputCmd 'upgrade' | Should -Be 'upgrade'
    }

    It 'Get-CommandSuggestion prefers prefix matches' {
        Get-CommandSuggestion -InputCmd 'upg' | Should -Be 'upgrade'
        Get-CommandSuggestion -InputCmd 'dia' | Should -Be 'diag'
        Get-CommandSuggestion -InputCmd 'sched' | Should -Be 'schedule'
    }

    It 'Get-CommandSuggestion returns null for weak matches' {
        Get-CommandSuggestion -InputCmd 'z' | Should -Be $null
    }

    It 'Get-CommandSuggestion handles doctor/purge typos' {
        Get-CommandSuggestion -InputCmd 'doct' | Should -Be 'doctor'
        Get-CommandSuggestion -InputCmd 'purg' | Should -Be 'purge'
    }
}
