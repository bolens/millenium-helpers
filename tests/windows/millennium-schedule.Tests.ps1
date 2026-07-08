# Pester tests for Windows schedule script
$winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"

# Dot-source the common module with dry-run forced
$global:DryRun = $true
. (Join-Path -Path $winScriptDir -ChildPath "common.ps1")

Describe "Schedule CLI Manager" {
    Context "Wizard setup" {
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }
        
        # Mock Read-Host inputs for wizard: 2 (beta channel), y (daily timer), empty (token)
        $inputs = @("2", "y", "")
        $script:inputIdx = 0
        Mock Read-Host {
            $val = $inputs[$script:inputIdx]
            $script:inputIdx++
            return $val
        }
        Mock Register-ScheduledTask { return $true }
        Mock New-ScheduledTaskAction { return $true }
        Mock New-ScheduledTaskTrigger { return $true }
        Mock New-ScheduledTaskSettingsSet { return $true }
        Mock Test-Admin { return $true }

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
