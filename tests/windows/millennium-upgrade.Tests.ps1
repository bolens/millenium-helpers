Describe "Upgrade Script" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name C -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
        }
        function Get-Content {
            param(
                [string]$Path,
                [switch]$Raw
            )
            if ($Path -like "*relaunch_state.json*") {
                return '{"Executable":"C:\\MockedSteam\\steam.exe","Arguments":"","SteamRunning":true}'
            }
            return "3.0.0"
        }
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
    }

    Context "Upgrade Validation" {
        It "Validates channels successfully" {
            $upgradeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-upgrade.ps1"
            
            # Test invalid channel exits with non-zero
            $proc = Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$upgradeScript`" -Channel invalid -DryRun" -PassThru -Wait -NoNewWindow
            $proc.ExitCode | Should -Not -Be 0
        }
    }

    Context "Upgrade Dry-Run" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path {
                if ($Path -like "*millennium_backups*") { return $false }
                return $true
            }
            Mock Invoke-RestMethod { return [pscustomobject]@{ tag_name = "v3.3.1" } }
        }

        It "Succeeds dry-run on stable channel upgrade" {
            $upgradeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-upgrade.ps1"
            $out = (& $upgradeScript -Channel stable -DryRun *>&1) | Out-String
            $out | Should -BeLike "*Would download*"
        }
    }
}
