Describe "Repair Script" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        function Stop-Process { }
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name C -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
        }
        function Get-ScheduledTask { }
        function Get-Content {
            param(
                [string]$Path,
                [switch]$Raw
            )
            return '{"update_channel":"beta","github_token":""}'
        }
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
    }

    Context "Force Repair Execution" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path { return $true }
            Mock Get-Process { return $null }
            Mock Get-ScheduledTask { return $null }
            Mock Test-Admin { return $true }
        }

        It "Runs the repair logic without errors" {
            $repairScript = Join-Path -Path $winScriptDir -ChildPath "millennium-repair.ps1"
            $out = (& $repairScript -DryRun *>&1) | Out-String
            $out | Should -BeLike "*Initiating Millennium Force Repair*"
            $out | Should -BeLike "*Repair completed successfully.*"
        }
    }
}
