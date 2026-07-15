Describe "PowerShell completions" {
    BeforeAll {
        $repoRoot = Join-Path -Path $PSScriptRoot -ChildPath "..\.."
        $completionScript = Join-Path -Path $repoRoot -ChildPath "completions\powershell\millennium-helpers.ps1"
        . $completionScript
    }

    It "Defines dispatcher and schedule helper commands" {
        Get-Command Get-MillenniumDispatcherCommands | Should -Not -BeNullOrEmpty
        Get-Command Get-MillenniumScheduleActions | Should -Not -BeNullOrEmpty
        (Get-MillenniumDispatcherCommands) | Should -Contain "diag"
        (Get-MillenniumDispatcherCommands) | Should -Contain "schedule"
        (Get-MillenniumScheduleActions) | Should -Contain "enable"
        (Get-MillenniumScheduleActions) | Should -Contain "setup"
    }

    It "Completes millennium dispatcher commands" {
        $cmd = [System.Management.Automation.Language.Parser]::ParseInput(
            "millennium ",
            [ref]$null,
            [ref]$null
        ).EndBlock.Statements[0].PipelineElements[0]
        $results = @(Complete-MillenniumNative -CommandName "millennium" -WordToComplete "" -CommandAst $cmd -CursorPosition 11)
        $values = @($results | ForEach-Object { $_.CompletionText })
        $values | Should -Contain "diag"
        $values | Should -Contain "schedule"
        $values | Should -Contain "doctor"
    }

    It "Completes millennium schedule nested actions" {
        $cmd = [System.Management.Automation.Language.Parser]::ParseInput(
            "millennium schedule ",
            [ref]$null,
            [ref]$null
        ).EndBlock.Statements[0].PipelineElements[0]
        $results = @(Complete-MillenniumNative -CommandName "millennium" -WordToComplete "" -CommandAst $cmd -CursorPosition 20)
        $values = @($results | ForEach-Object { $_.CompletionText })
        $values | Should -Contain "enable"
        $values | Should -Contain "status"
        $values | Should -Contain "config"
    }

    It "Completes millennium schedule enable channels" {
        $cmd = [System.Management.Automation.Language.Parser]::ParseInput(
            "millennium schedule enable ",
            [ref]$null,
            [ref]$null
        ).EndBlock.Statements[0].PipelineElements[0]
        $results = @(Complete-MillenniumNative -CommandName "millennium" -WordToComplete "" -CommandAst $cmd -CursorPosition 27)
        $values = @($results | ForEach-Object { $_.CompletionText })
        $values | Should -Contain "stable"
        $values | Should -Contain "beta"
    }

    It "Filters schedule actions by prefix" {
        $cmd = [System.Management.Automation.Language.Parser]::ParseInput(
            "millennium schedule en",
            [ref]$null,
            [ref]$null
        ).EndBlock.Statements[0].PipelineElements[0]
        $results = @(Complete-MillenniumNative -CommandName "millennium" -WordToComplete "en" -CommandAst $cmd -CursorPosition 22)
        $values = @($results | ForEach-Object { $_.CompletionText })
        $values | Should -Contain "enable"
        $values | Should -Not -Contain "disable"
    }
}
