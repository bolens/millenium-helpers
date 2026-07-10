Describe "Common Helpers" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        function Stop-Process { }
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name HKLM -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name C -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            function Get-CimInstance { }
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

        It "Does not print DEBUG noise by default" {
            $out = Resolve-SteamPath *>&1 | Out-String
            $out | Should -Not -BeLike "*DEBUG:*"
        }

        It "Get-HelpersVersion reads the repo VERSION file" {
            $ver = Get-HelpersVersion
            $ver | Should -Be "2.2.0"
        }

        It "Write-HelpersVersion prints command name and version" {
            $out = Write-HelpersVersion -Name "millennium-test"
            $out | Should -Be "millennium-test 2.2.0"
        }

        It "Write-DebugMsg stays quiet unless MILLENNIUM_DEBUG is set" {
            $prev = $env:MILLENNIUM_DEBUG
            try {
                Remove-Item Env:MILLENNIUM_DEBUG -ErrorAction SilentlyContinue
                $quiet = Write-DebugMsg "should-not-appear" *>&1 | Out-String
                $quiet | Should -Not -BeLike "*DEBUG:*"

                $env:MILLENNIUM_DEBUG = "1"
                $noisy = Write-DebugMsg "should-appear" *>&1 | Out-String
                $noisy | Should -BeLike "*DEBUG: should-appear*"
            } finally {
                if ($null -eq $prev) {
                    Remove-Item Env:MILLENNIUM_DEBUG -ErrorAction SilentlyContinue
                } else {
                    $env:MILLENNIUM_DEBUG = $prev
                }
            }
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

    Context "Steam Lifecycle - Capture and Relaunch" {
        BeforeAll {
            # Use temp directory for relaunch state file
            $env:LOCALAPPDATA = [System.IO.Path]::GetTempPath()
            
            Mock Get-Process {
                return [pscustomobject]@{ Name = "steam"; Id = 1234; Path = "C:\MockedSteam\steam.exe" }
            }
            Mock Get-CimInstance {
                return [pscustomobject]@{ CommandLine = '"C:\MockedSteam\steam.exe" -tenfoot -login username' }
            }
            Mock Start-Process { return $true }
            
            . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
        }

        It "Captures Steam launch arguments and executable path correctly" {
            # Run Capture with DryRun = $false temporarily to write state file
            $global:DryRun = $false
            Capture-SteamEnv
            $global:DryRun = $true

            $stateFile = Get-RelaunchStateFile
            Test-Path -Path $stateFile | Should -Be $true
            
            $state = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
            $state.SteamRunning | Should -Be $true
            $state.Executable | Should -Be "C:\MockedSteam\steam.exe"
            $state.Arguments | Should -Be "-tenfoot -login username"
        }

        It "Relaunches Steam using the saved state" {
            # Restore state file and run relaunch
            $global:DryRun = $false
            
            Mock Start-Process {
                param($FilePath, $ArgumentList)
                $script:startedFile = $FilePath
                $script:startedArgs = $ArgumentList
                return $true
            }
            
            Relaunch-Steam
            $global:DryRun = $true

            $script:startedFile | Should -Be "C:\MockedSteam\steam.exe"
            $script:startedArgs | Should -Be "-tenfoot -login username"

            # State file should have been cleaned up
            Test-Path -Path (Get-RelaunchStateFile) | Should -Be $false
        }
    }

    Context "Steam Lifecycle - Close Gracefully" {
        BeforeAll {
            $script:processCheckedCount = 0
            Mock Get-Process {
                $script:processCheckedCount++
                if ($script:processCheckedCount -eq 1) {
                    return [pscustomobject]@{ Name = "steam" }
                }
                return $null
            }
            Mock Test-Path { return $true }
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Start-Process {
                param($FilePath, $ArgumentList, $Wait)
                $script:startedGracefulFile = $FilePath
                $script:startedGracefulArgs = $ArgumentList
                return $true
            }
            
            . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
        }

        It "Closes steam client gracefully using -shutdown argument" {
            Close-SteamGracefully
            ($script:startedGracefulFile -replace '\\', '/') | Should -Be "C:/MockedSteam/steam.exe"
            $script:startedGracefulArgs | Should -Be "-shutdown"
        }
    }
}
