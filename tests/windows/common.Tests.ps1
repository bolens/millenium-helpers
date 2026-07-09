Describe "Common Helpers" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name HKLM -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Context "Steam Path Resolution - HKCU" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteamPath" } }
            Mock Test-Path { return $true }
            . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
        }

        It "Successfully resolves SteamPath from HKCU registry" {
            $path = Resolve-SteamPath
            $path | Should -Be "C:\MockedSteamPath"
        }
    }

    Context "Steam Path Resolution - Fallback" {
        BeforeAll {
            $script:oldProgFiles = $env:ProgramFiles
            $env:ProgramFiles = "C:\Program Files"
            Mock Get-ItemProperty { return $null }
            Mock Test-Path {
                Write-Host "DEBUG: Test-Path mock path is: '$Path'"
                if ($Path -like "*Program Files*") {
                    return $true
                }
                return $false
            }
            . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
        }
        AfterAll {
            $env:ProgramFiles = $script:oldProgFiles
        }

        It "Falls back to Program Files folder when registry is missing" {
            $path = Resolve-SteamPath
            $path | Should -BeLike "*Steam"
        }
    }

    Context "Process Checks - Active Game" {
        BeforeAll {
            Mock Get-Process {
                return @(
                    [pscustomobject]@{ Name = "svchost"; Path = "C:\Windows\System32\svchost.exe" },
                    [pscustomobject]@{ Name = "supergame"; Path = "D:\Steam\steamapps\common\SuperGame\game.exe" }
                )
            }
            . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
        }

        It "Detects active running games by checking steamapps path segment" {
            $isRunning = Is-GameRunning
            $isRunning | Should -Be $true
        }
    }

    Context "Process Checks - No Active Game" {
        BeforeAll {
            Mock Get-Process {
                return @(
                    [pscustomobject]@{ Name = "explorer"; Path = "C:\Windows\explorer.exe" }
                )
            }
            . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
        }

        It "Returns false when no game runs from steamapps" {
            $isRunning = Is-GameRunning
            $isRunning | Should -Be $false
        }
    }
}
