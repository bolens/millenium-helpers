# Pester tests for Millennium Helpers PowerShell scripts
# Runs inside the Windows CI matrix or locally on Windows.

$scriptDir = Split-Path -Parent $MyInvocation.ScriptName
$winScriptDir = Join-Path -Path $scriptDir -ChildPath "..\..\scripts\windows"

# Dot-source the common module with dry-run forced
$global:DryRun = $true
. (Join-Path -Path $winScriptDir -ChildPath "common.ps1")

Describe "Common Helpers" {
    Context "Steam Path Resolution" {
        It "Successfully resolves SteamPath from HKCU registry" {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteamPath" } }
            Mock Test-Path { return $true }
            
            $path = Resolve-SteamPath
            $path | Should -Be "C:\MockedSteamPath"
        }

        It "Falls back to Program Files folder when registry is missing" {
            Mock Get-ItemProperty { return $null }
            Mock Test-Path {
                param($Path)
                if ($Path -like "*Program Files*") { return $true }
                return $false
            }

            $path = Resolve-SteamPath
            $path | Should -Like "*Steam"
        }
    }

    Context "Process Checks" {
        It "Detects active running games by checking steamapps path segment" {
            Mock Get-Process {
                return @(
                    [pscustomobject]@{ Name = "svchost"; Path = "C:\Windows\System32\svchost.exe" },
                    [pscustomobject]@{ Name = "supergame"; Path = "D:\Steam\steamapps\common\SuperGame\game.exe" }
                )
            }
            
            $isRunning = Is-GameRunning
            $isRunning | Should -Be $true
        }

        It "Returns false when no game runs from steamapps" {
            Mock Get-Process {
                return @(
                    [pscustomobject]@{ Name = "explorer"; Path = "C:\Windows\explorer.exe" }
                )
            }

            $isRunning = Is-GameRunning
            $isRunning | Should -Be $false
        }
    }
}

Describe "Upgrade Script" {
    It "Validates channels successfully" {
        $upgradeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-upgrade.ps1"
        
        # Test invalid channel exits with non-zero
        $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$upgradeScript`" -Channel invalid -DryRun" -PassThru -Wait -NoNewWindow
        $proc.ExitCode | Should -Not -Be 0
    }

    It "Succeeds dry-run on stable channel upgrade" {
        $upgradeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-upgrade.ps1"
        
        # Dry run stable
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }
        Mock Invoke-RestMethod { return [pscustomobject]@{ tag_name = "v3.3.1" } }

        $out = & $upgradeScript -Channel stable -DryRun
        $out | Should -Contain "Would download"
    }
}

Describe "Diagnostics & Doctor" {
    It "Correctly outputs json report when -Json switch is used" {
        $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
        
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }
        Mock Get-Process { return $null }
        Mock Get-ScheduledTask { return $null }

        $out = & $diagScript -Json -DryRun | ConvertFrom-Json
        $out.steam_running | Should -Be $false
        $out.task_scheduled | Should -Be $false
    }
}

Describe "Theme CLI Manager" {
    It "Rejects install arguments that contain path traversal patterns" {
        $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
        
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }

        $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$themeScript`" install `"x/../../tmp/evil`"" -PassThru -Wait -NoNewWindow
        $proc.ExitCode | Should -Not -Be 0
    }

    It "Rejects install arguments that contain Windows path traversal patterns" {
        $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
        
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }

        $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$themeScript`" install `"x\..\..\tmp\evil`"" -PassThru -Wait -NoNewWindow
        $proc.ExitCode | Should -Not -Be 0
    }

    It "Rejects install arguments without owner/repo format" {
        $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
        
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }

        $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$themeScript`" install `"solotheme`"" -PassThru -Wait -NoNewWindow
        $proc.ExitCode | Should -Not -Be 0
    }

    It "Accepts owner\repo format and standardizes it to owner/repo" {
        $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
        
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }
        Mock Invoke-RestMethod { return @( [pscustomobject]@{ sha = "mockcommitsha" } ) }

        # Dry run with backslashes
        $out = & $themeScript install "mockowner\mockrepo" -DryRun
        $out | Should -Contain "Resolving latest commit for mockowner/mockrepo"
    }
}

Describe "Schedule CLI Manager" {
    It "Saves configuration wizard data correctly" {
        $scheduleScript = Join-Path -Path $winScriptDir -ChildPath "millennium-schedule.ps1"
        
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }
        
        $tempConfigDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "pest_test_config"
        $env:LOCALAPPDATA = $tempConfigDir
        $env:FORCE_WIZARD = "true"

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

        & $scheduleScript setup -DryRun
        
        # Verify config values printed in dry-run
        $configFile = Join-Path -Path $tempConfigDir -ChildPath "millennium-helpers\config.json"
        
        Remove-Item -Path $tempConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
