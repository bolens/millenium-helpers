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

    Context "Help and Version" {
        It "Prints usage with -Help" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript -Help *>&1) | Out-String
            $out | Should -BeLike "*Usage:*"
            $out | Should -BeLike "*doctor*"
            $out | Should -BeLike "*logs*"
            $out | Should -BeLike "*-Yes*"
        }

        It "Prints version with -Version" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript -Version *>&1) | Out-String
            $out | Should -BeLike "*millennium-diag*"
        }
    }

    Context "Human-readable report next steps" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path { return $true }
            Mock Get-Process { return $null }
            Mock Get-ScheduledTask { return $null }
        }

        It "Prints next-steps footer suggesting doctor when task is missing" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript -DryRun *>&1) | Out-String
            $out | Should -BeLike "*issue(s) detected*"
            $out | Should -BeLike "*millennium doctor*"
            $out | Should -BeLike "*WARN*"
        }
    }

    Context "Logs command" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path {
                if ($Path -like "*logs*") { return $false }
                return $true
            }
            Mock Get-Process { return $null }
            Mock Get-ScheduledTask { return $null }
        }

        It "Fails clearly when no Steam logs exist" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $proc = Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$diagScript`" logs" -PassThru -Wait -NoNewWindow -RedirectStandardError ([IO.Path]::GetTempFileName()) -RedirectStandardOutput ([IO.Path]::GetTempFileName())
            $proc.ExitCode | Should -Not -Be 0
        }
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
            $out = & $diagScript -Share -DryRun *>&1 | Out-String
            $out | Should -Match "Diagnostic report successfully shared!"
            $out | Should -Match "https://paste.rs/mocklink"
        }
    }
}
