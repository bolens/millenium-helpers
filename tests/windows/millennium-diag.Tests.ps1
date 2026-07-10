Describe "Diagnostics & Doctor" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
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
            return "3.0.0"
        }
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
    }

    Context "JSON Diagnostics" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path { return $true }
            Mock Get-Process { return $null }
            Mock Get-ScheduledTask { return $null }
        }

        It "Correctly outputs json report when -Json switch is used" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = & $diagScript -Json -DryRun | ConvertFrom-Json
            $out.steam_running | Should -Be $false
            $out.task_scheduled | Should -Be $false
        }
    }

    Context "Diagnostics Sharing" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path { return $true }
            Mock Get-Process { return $null }
            Mock Get-ScheduledTask { return $null }
            Mock Invoke-RestMethod { return "https://paste.rs/mocklink" }
        }

        It "Correctly shares the report output and prints URL" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = & $diagScript -Share -DryRun | Out-String
            $out | Should -Contain "Diagnostic report successfully shared!"
            $out | Should -Contain "https://paste.rs/mocklink"
        }
    }
}
