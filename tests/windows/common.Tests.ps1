Describe "Common Helpers" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        $global:Quiet = $false
        Remove-Item Env:MILLENNIUM_QUIET -ErrorAction SilentlyContinue
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
            $expected = (Get-Content -Path (Join-Path $PSScriptRoot "..\..\VERSION") -Raw).Trim()
            $ver = Get-HelpersVersion
            $ver | Should -Be $expected
        }

        It "Write-HelpersVersion prints command name and version" {
            $expected = (Get-Content -Path (Join-Path $PSScriptRoot "..\..\VERSION") -Raw).Trim()
            $out = Write-HelpersVersion -Name "millennium-test"
            $out | Should -Be "millennium-test $expected"
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

        It "Log-Info respects MILLENNIUM_QUIET" {
            $prev = $env:MILLENNIUM_QUIET
            try {
                $env:MILLENNIUM_QUIET = "1"
                $out = Log-Info "hidden-info" *>&1 | Out-String
                $out | Should -Not -BeLike "*hidden-info*"
            } finally {
                if ($null -eq $prev) {
                    Remove-Item Env:MILLENNIUM_QUIET -ErrorAction SilentlyContinue
                } else {
                    $env:MILLENNIUM_QUIET = $prev
                }
            }
        }

        It "Write-UpgradeFailureTips mentions rollback and diag" {
            $out = Write-UpgradeFailureTips -Detail "download failed" *>&1 | Out-String
            $out | Should -BeLike "*Upgrade failed*"
            $out | Should -BeLike "*rollback*"
            $out | Should -BeLike "*millennium diag*"
        }

        It "Apply-GnuStyleArgs maps --json and --yes" {
            $flags = @{ Json = $false; Yes = $false; DryRun = $false }
            $rest = Apply-GnuStyleArgs -InputArgs @("--json", "list", "--yes") -Target $flags
            $flags.Json | Should -Be $true
            $flags.Yes | Should -Be $true
            $rest | Should -Contain "list"
        }

        It "Apply-GnuStyleArgs maps channel shortcuts and --channel value" {
            $flags = @{ Channel = $null; Force = $false }
            $rest = Apply-GnuStyleArgs -InputArgs @("--main", "extra") -Target $flags
            $flags.Channel | Should -Be "main"
            $rest | Should -Contain "extra"

            $flags2 = @{ Channel = $null; Force = $false; File = $null; Rollback = $null; SkipTheme = $false }
            $rest2 = Apply-GnuStyleArgs -InputArgs @("--channel", "beta", "--force", "--file", "C:\a.zip", "--rollback", "list", "--skip-theme") -Target $flags2
            $flags2.Channel | Should -Be "beta"
            $flags2.Force | Should -Be $true
            $flags2.File | Should -Be "C:\a.zip"
            $flags2.Rollback | Should -Be "list"
            $flags2.SkipTheme | Should -Be $true
            @($rest2).Count | Should -Be 0
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

    Context "Confirm-CloseSteam" {
        BeforeAll {
            $script:closeCalled = $false
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path { return $true }
            . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
            Mock Close-SteamGracefully { $script:closeCalled = $true }
        }

        It "Returns true immediately when Steam is not running" {
            Mock Get-Process { return $null }
            $script:closeCalled = $false
            $result = Confirm-CloseSteam
            $result | Should -Be $true
            $script:closeCalled | Should -Be $false
        }

        It "Auto-confirms and closes when -Yes is passed" {
            Mock Get-Process {
                if ($Name -eq "steam") {
                    return [pscustomobject]@{ Id = 1234; Name = "steam" }
                }
                return $null
            }
            $script:closeCalled = $false
            $prev = $env:PSTESTS
            Remove-Item Env:PSTESTS -ErrorAction SilentlyContinue
            $global:AssumeYes = $false
            try {
                $result = Confirm-CloseSteam -Yes
                $result | Should -Be $true
                $script:closeCalled | Should -Be $true
            } finally {
                if ($null -ne $prev) { $env:PSTESTS = $prev }
            }
        }

        It "Auto-confirms under PSTESTS without prompting" {
            Mock Get-Process {
                if ($Name -eq "steam") {
                    return [pscustomobject]@{ Id = 1234; Name = "steam" }
                }
                return $null
            }
            $script:closeCalled = $false
            $env:PSTESTS = "true"
            $global:AssumeYes = $false
            $result = Confirm-CloseSteam
            $result | Should -Be $true
            $script:closeCalled | Should -Be $true
        }
    }

    Context "Get-ClosestToken" {
        BeforeAll {
            . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
        }

        It "Maps lst to list via subsequence" {
            Get-ClosestToken -InputToken "lst" -Candidates @("list", "install", "update", "remove") | Should -Be "list"
        }

        It "Maps stauts to status" {
            Get-ClosestToken -InputToken "stauts" -Candidates @("enable", "disable", "status", "setup") | Should -Be "status"
        }

        It "Returns null for unrelated input" {
            Get-ClosestToken -InputToken "zzzz" -Candidates @("list", "install") | Should -Be $null
        }
    }

    Context "Protect-HelpersConfigFile" {
        BeforeAll {
            . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
        }

        It "No-ops when the config file is missing" {
            $tempRoot = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
            { Protect-HelpersConfigFile -Path (Join-Path $tempRoot "mh-missing-config.json") } | Should -Not -Throw
        }

        It "Locks down ACL inheritance on Windows" {
            if ($env:OS -ne 'Windows_NT') {
                Set-ItResult -Skipped -Because "ACL lockdown is Windows-only"
                return
            }
            $tempRoot = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
            $tmp = Join-Path -Path $tempRoot -ChildPath "mh-acl-config.json"
            '{"github_token":"secret"}' | Set-Content -Path $tmp -Force
            try {
                Protect-HelpersConfigFile -Path $tmp
                $acl = Get-Acl -Path $tmp
                $acl.AreAccessRulesProtected | Should -Be $true
            } finally {
                Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
