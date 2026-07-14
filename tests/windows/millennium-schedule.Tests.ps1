Describe "Schedule CLI Manager" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name C -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
        }
        function Register-ScheduledTask { }
        function Get-ScheduledTask { }
        function New-ScheduledTaskAction { }
        function New-ScheduledTaskTrigger { }
        function New-ScheduledTaskSettingsSet { }
        function Get-Content {
            param(
                [Parameter(ValueFromPipeline = $true)]
                [string]$Path,
                [switch]$Raw,
                [string]$LiteralPath
            )
            $p = if ($LiteralPath) { $LiteralPath } else { $Path }
            if ($p -like "*config.json*") {
                # Defer to real Get-Content so config tests can read written files.
                return Microsoft.PowerShell.Management\Get-Content -LiteralPath $p -Raw:$Raw
            }
            if ($p -like "*VERSION*") {
                return "3.0.0"
            }
            return Microsoft.PowerShell.Management\Get-Content @PSBoundParameters
        }
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
    }

    Context "Help and Version" {
        It "Prints usage with -Help" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript -Help *>&1) | Out-String
            $out | Should -BeLike "*Usage:*"
            $out | Should -BeLike "*enable*"
            $out | Should -BeLike "*setup*"
            $out | Should -BeLike "*-DryRun*"
            $out | Should -BeLike "*GNU-style*"
        }

        It "Prints version with -Version" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript -Version *>&1) | Out-String
            $out | Should -BeLike "*millennium-schedule*"
        }

        It "Suggests closest command on typo" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript stauts *>&1) | Out-String
            $out | Should -BeLike "*Unknown command*"
            $out | Should -BeLike "*Did you mean*status*"
        }
    }

    Context "status when registered" {
        It "Prints scheduler summary with disable CTA" {
            Mock Get-ScheduledTask {
                return [pscustomobject]@{
                    TaskName = "MillenniumUpdate"
                    TaskPath = "\"
                    State = "Ready"
                    Actions = @([pscustomobject]@{ Execute = "powershell.exe"; Arguments = "-File upgrade.ps1 -Channel beta" })
                }
            }
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript status *>&1) | Out-String
            $out | Should -BeLike "*Scheduler summary*"
            $out | Should -BeLike "*millennium schedule disable*"
            $out | Should -BeLike "*Channel*"
        }
    }

    Context "Wizard setup" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path { return $true }

            # Mock Read-Host inputs for wizard: 2 (beta channel), y (daily timer), empty (token)
            $inputs = @("2", "y", "")
            $global:readHostIdx = 0
            Mock Read-Host {
                $val = $inputs[$global:readHostIdx]
                $global:readHostIdx++
                return $val
            }
            Mock Register-ScheduledTask { return $true }
            Mock Get-ScheduledTask { return $null }
            Mock New-ScheduledTaskAction { return $true }
            Mock New-ScheduledTaskTrigger { return $true }
            Mock New-ScheduledTaskSettingsSet { return $true }
            Mock Test-Admin { return $true }
        }

        It "Saves configuration wizard data correctly" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $tempConfigDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "pest_test_config"
            $env:LOCALAPPDATA = $tempConfigDir
            $env:FORCE_WIZARD = "true"

            $out = (& $scheduleScript setup -DryRun *>&1) | Out-String
            $out | Should -BeLike "*backup_limit*"
            $out | Should -Match "github_token\s+:\s+(\[set\]|\(not set\))"

            Remove-Item -Path $tempConfigDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Status CTA" {
        BeforeAll {
            Mock Get-ScheduledTask { return $null }
        }

        It "Prints enable command when task is not registered" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript status *>&1) | Out-String
            $out | Should -BeLike "*Scheduler disabled*"
            $out | Should -BeLike "*millennium schedule enable*"
        }
    }

    Context "config get/set/list" {
        BeforeEach {
            $script:tempConfigDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mh_sched_cfg_" + [guid]::NewGuid().ToString("n"))
            $env:LOCALAPPDATA = $script:tempConfigDir
            $cfgDir = Join-Path $script:tempConfigDir "millennium-helpers"
            New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
            '{"update_channel":"stable","github_token":"tok1234","backup_limit":3}' |
                Set-Content -Path (Join-Path $cfgDir "config.json") -Encoding utf8
        }
        AfterEach {
            Remove-Item -Path $script:tempConfigDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Lists config including backup keys" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript config list *>&1) | Out-String
            $out | Should -BeLike "*update_channel*"
            $out | Should -BeLike "*backup_limit*"
            $out | Should -BeLike "*github_token*"
        }

        It "Sets update_channel to main" {
            $prevDry = $global:DryRun
            $global:DryRun = $false
            try {
                $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
                & $scheduleScript config set update_channel main *>&1 | Out-Null
                $cfgPath = Join-Path $env:LOCALAPPDATA "millennium-helpers\config.json"
                $raw = Microsoft.PowerShell.Management\Get-Content -LiteralPath $cfgPath -Raw
                $data = $raw | ConvertFrom-Json
                $data.update_channel | Should -Be "main"
                $data.backup_limit | Should -Be 3
            } finally {
                $global:DryRun = $prevDry
            }
        }

        It "Gets a config value" {
            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript config get update_channel *>&1) | Out-String
            $out.Trim() | Should -Be "stable"
        }
    }

    Context "enable task action parity" {
        It "Registers task with -Yes -Quiet, theme update, and updater.log redirect" {
            Mock Test-Admin { return $true }
            Mock New-ScheduledTaskAction { return [pscustomobject]@{} }
            Mock New-ScheduledTaskTrigger {
                $t = [pscustomobject]@{}
                $t | Add-Member -NotePropertyName RandomDelay -NotePropertyValue $null -Force
                return $t
            }
            Mock New-ScheduledTaskSettingsSet { return [pscustomobject]@{} }
            Mock Register-ScheduledTask { return $true }

            $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
            $out = (& $scheduleScript enable beta -DryRun *>&1) | Out-String
            $out | Should -BeLike "*-Yes*"
            $out | Should -BeLike "*-Quiet*"
            $out | Should -BeLike "*updater.log*"
            $out | Should -BeLike "*millennium-theme.ps1*"
            $out | Should -BeLike "*update*"
            $out | Should -BeLike "*-Channel*beta*"
        }
    }
}
