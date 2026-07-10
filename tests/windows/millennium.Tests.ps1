Describe "Millennium dispatcher" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
    }

    It "Help documents doctor alias" {
        $dispatcher = Join-Path -Path $winScriptDir -ChildPath "millennium.ps1"
        $out = (& $dispatcher help *>&1) | Out-String
        $out | Should -BeLike "*Usage:*"
        $out | Should -BeLike "*doctor*"
        $out | Should -BeLike "*diag*"
    }

    It "Suggests closest command on typo" {
        $dispatcher = Join-Path -Path $winScriptDir -ChildPath "millennium.ps1"
        $out = (& $dispatcher upgrad *>&1) | Out-String
        $out | Should -BeLike "*Unknown command*"
        $out | Should -BeLike "*Did you mean*upgrade*"
    }
}
