# Pester tests for Windows common helpers
$winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"

# Dot-source the common module with dry-run forced
$global:DryRun = $true
. (Join-Path -Path $winScriptDir -ChildPath "common.ps1")

Describe "Common Helpers" {
    Context "Steam Path Resolution - HKCU" {
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteamPath" } }
        Mock Test-Path { return $true }

        It "Successfully resolves SteamPath from HKCU registry" {
            $path = Resolve-SteamPath
            $path | Should -Be "C:\MockedSteamPath"
        }
    }

    Context "Steam Path Resolution - Fallback" {
        Mock Get-ItemProperty { return $null }
        Mock Test-Path {
            param($Path)
            if ($Path -like "*Program Files*") { return $true }
            return $false
        }

        It "Falls back to Program Files folder when registry is missing" {
            $path = Resolve-SteamPath
            $path | Should -Like "*Steam"
        }
    }

    Context "Process Checks - Active Game" {
        Mock Get-Process {
            return @(
                [pscustomobject]@{ Name = "svchost"; Path = "C:\Windows\System32\svchost.exe" },
                [pscustomobject]@{ Name = "supergame"; Path = "D:\Steam\steamapps\common\SuperGame\game.exe" }
            )
        }

        It "Detects active running games by checking steamapps path segment" {
            $isRunning = Is-GameRunning
            $isRunning | Should -Be $true
        }
    }

    Context "Process Checks - No Active Game" {
        Mock Get-Process {
            return @(
                [pscustomobject]@{ Name = "explorer"; Path = "C:\Windows\explorer.exe" }
            )
        }

        It "Returns false when no game runs from steamapps" {
            $isRunning = Is-GameRunning
            $isRunning | Should -Be $false
        }
    }
}
