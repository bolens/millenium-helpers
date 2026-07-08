# Pester tests for Windows diag script
$winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"

# Dot-source the common module with dry-run forced
$global:DryRun = $true
. (Join-Path -Path $winScriptDir -ChildPath "common.ps1")

Describe "Diagnostics & Doctor" {
    Context "JSON Diagnostics" {
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }
        Mock Get-Process { return $null }
        Mock Get-ScheduledTask { return $null }

        It "Correctly outputs json report when -Json switch is used" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = & $diagScript -Json -DryRun | ConvertFrom-Json
            $out.steam_running | Should -Be $false
            $out.task_scheduled | Should -Be $false
        }
    }
}
