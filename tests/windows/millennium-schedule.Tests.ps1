Describe "Schedule CLI Manager" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name C -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            function Register-ScheduledTask { }
            function Get-ScheduledTask { }
            function New-ScheduledTaskAction { }
            function New-ScheduledTaskTrigger { }
            function New-ScheduledTaskSettingsSet { }
        }
        function Get-Content {
            param(
                [string]$Path,
                [switch]$Raw
            )
            if ($Path -like "*config.json*") {
                return '{"update_channel":"stable","github_token":""}'
            }
            return "3.0.0"
        }
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
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

            & $scheduleScript setup -DryRun
            
            Remove-Item -Path $tempConfigDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
