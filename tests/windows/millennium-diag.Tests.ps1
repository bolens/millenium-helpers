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
            # Provide a real writable temp dir so Resolve-SteamPath is bypassed portably.
            # task_scheduled=false because Get-ScheduledTask function (defined in BeforeAll) returns null.
            $env:DIAG_TEST_STEAM_PATH = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        }
        AfterAll {
            $env:DIAG_TEST_STEAM_PATH = $null
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
            # task_scheduled=false: Get-ScheduledTask function (defined in BeforeAll) returns null.
            $env:DIAG_TEST_STEAM_PATH = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        }
        AfterAll {
            $env:DIAG_TEST_STEAM_PATH = $null
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

    # -----------------------------------------------------------------------
    # New contexts: install method detection, update checks, doctor ordering
    # -----------------------------------------------------------------------

    Context "JSON includes install_method fields (manual + bypass)" {
        BeforeAll {
            $env:DIAG_TEST_STEAM_PATH      = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $env:DIAG_TEST_INSTALL_METHOD  = "manual"
            $env:DIAG_TEST_BYPASS_CHECKS   = "true"
            $env:DIAG_TEST_CHECKOUT        = "C:\fake\dev\millenium-helpers"
        }
        AfterAll {
            $env:DIAG_TEST_STEAM_PATH      = $null
            $env:DIAG_TEST_INSTALL_METHOD  = $null
            $env:DIAG_TEST_BYPASS_CHECKS   = $null
            $env:DIAG_TEST_CHECKOUT        = $null
        }

        It "JSON output includes install_method, mixed_install_ok, scripts_up_to_date, helpers_checkout" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = & $diagScript -Json -DryRun | ConvertFrom-Json
            $out.install_method     | Should -Be "manual"
            $out.mixed_install_ok   | Should -Be $true
            $out.scripts_up_to_date | Should -Be $true
            $out.helpers_checkout   | Should -Be "C:\fake\dev\millenium-helpers"
            $out.completions_ok     | Should -Be $true
        }
    }

    Context "Completions health in JSON and next-steps" {
        BeforeAll {
            $env:DIAG_TEST_STEAM_PATH       = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $env:DIAG_TEST_INSTALL_METHOD   = "manual"
            $env:DIAG_TEST_BYPASS_CHECKS    = "true"
            $env:DIAG_TEST_COMPLETIONS_OK   = "false"
        }
        AfterAll {
            $env:DIAG_TEST_STEAM_PATH       = $null
            $env:DIAG_TEST_INSTALL_METHOD   = $null
            $env:DIAG_TEST_BYPASS_CHECKS    = $null
            $env:DIAG_TEST_COMPLETIONS_OK   = $null
        }

        It "JSON reports completions_ok=false when DIAG_TEST_COMPLETIONS_OK=false" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = & $diagScript -Json -DryRun | ConvertFrom-Json
            $out.completions_ok | Should -Be $false
        }

        It "Next-steps suggest doctor for bad completions" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript -DryRun *>&1) | Out-String
            $out | Should -BeLike "*PowerShell completions*"
            $out | Should -BeLike "*millennium doctor*"
        }
    }

    Context "Mixed install detected in JSON and doctor dry-run" {
        BeforeAll {
            $env:DIAG_TEST_STEAM_PATH     = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $env:DIAG_TEST_INSTALL_METHOD = "mixed"
            $env:DIAG_TEST_BYPASS_CHECKS  = "true"
        }
        AfterAll {
            $env:DIAG_TEST_STEAM_PATH     = $null
            $env:DIAG_TEST_INSTALL_METHOD = $null
            $env:DIAG_TEST_BYPASS_CHECKS  = $null
        }

        It "JSON shows mixed_install_ok=false when install method is mixed" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = & $diagScript -Json -DryRun | ConvertFrom-Json
            $out.install_method   | Should -Be "mixed"
            $out.mixed_install_ok | Should -Be $false
        }

        It "Doctor dry-run output mentions Mixed install warning" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript doctor -DryRun *>&1) | Out-String
            $out | Should -BeLike "*Mixed*"
        }
    }

    Context "Scoop-packaged install in doctor dry-run refuses manual overwrite" {
        BeforeAll {
            $env:DIAG_TEST_STEAM_PATH      = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $env:DIAG_TEST_SCOOP_PACKAGED  = "true"
            $env:DIAG_TEST_INSTALL_METHOD  = "scoop"
            $env:DIAG_TEST_BYPASS_CHECKS   = "true"
        }
        AfterAll {
            $env:DIAG_TEST_STEAM_PATH      = $null
            $env:DIAG_TEST_SCOOP_PACKAGED  = $null
            $env:DIAG_TEST_INSTALL_METHOD  = $null
            $env:DIAG_TEST_BYPASS_CHECKS   = $null
        }

        It "Doctor dry-run for scoop install shows scoop upgrade hint, not file overwrite" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript doctor -DryRun -Force *>&1) | Out-String
            # Should suggest scoop update, not attempt to copy files
            $out | Should -BeLike "*scoop*"
            # Should NOT show individual script copy messages
            $out | Should -Not -BeLike "*Copy-Item*millennium-diag.ps1*"
        }

        It "Doctor -Yes -DryRun would run scoop update for outdated packaged install" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript doctor -DryRun -Force -Yes *>&1) | Out-String
            $out | Should -BeLike "*Would run: scoop update millennium-helpers*"
        }
    }

    Context "Winget package ID and -Yes dry-run upgrade" {
        BeforeAll {
            $env:DIAG_TEST_STEAM_PATH      = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $env:DIAG_TEST_WINGET_PACKAGED = "true"
            $env:DIAG_TEST_INSTALL_METHOD  = "winget"
            $env:DIAG_TEST_BYPASS_CHECKS   = "true"
        }
        AfterAll {
            $env:DIAG_TEST_STEAM_PATH      = $null
            $env:DIAG_TEST_WINGET_PACKAGED = $null
            $env:DIAG_TEST_INSTALL_METHOD  = $null
            $env:DIAG_TEST_BYPASS_CHECKS   = $null
        }

        It "Report uses bolens.millenniumhelpers winget ID" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript -DryRun *>&1) | Out-String
            $out | Should -BeLike "*bolens.millenniumhelpers*"
            $out | Should -Not -BeLike "*bolens.millennium-helpers*"
        }

        It "Doctor -Yes -DryRun would run winget upgrade with correct ID" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript doctor -DryRun -Force -Yes *>&1) | Out-String
            $out | Should -BeLike "*Would run: winget upgrade bolens.millenniumhelpers*"
        }
    }

    Context "Doctor obsolete cleanup runs before binary repair messaging" {
        BeforeAll {
            $env:DIAG_TEST_STEAM_PATH     = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            # Set an obsolete file in temp so it appears to exist
            $env:DIAG_TEST_OBSOLETE_LIST  = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "fake-obsolete-millennium.ps1")
            $env:DIAG_TEST_INSTALL_METHOD = "manual"
            $env:DIAG_TEST_BYPASS_CHECKS  = "true"
        }
        AfterAll {
            $env:DIAG_TEST_STEAM_PATH     = $null
            $env:DIAG_TEST_OBSOLETE_LIST  = $null
            $env:DIAG_TEST_INSTALL_METHOD = $null
            $env:DIAG_TEST_BYPASS_CHECKS  = $null
        }

        It "Cleanup section appears before binary repair in doctor dry-run output" {
            # Create the fake obsolete file so it registers
            $fakeObsolete = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "fake-obsolete-millennium.ps1"
            Set-Content -Path $fakeObsolete -Value "# fake" -ErrorAction SilentlyContinue

            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $diagScript doctor -DryRun -Force *>&1) | Out-String

            $cleanupIdx = $out.IndexOf("Cleaning up obsolete")
            $repairIdx  = $out.IndexOf("Repairing Millennium binaries")

            $cleanupIdx | Should -BeGreaterThan -1
            $repairIdx  | Should -BeGreaterThan -1
            $cleanupIdx | Should -BeLessThan $repairIdx

            Remove-Item -Path $fakeObsolete -ErrorAction SilentlyContinue
        }
    }

    Context "DIAG_TEST_RELEASE_EXTRACT mock path — manual install JSON still works" {
        BeforeAll {
            $env:DIAG_TEST_STEAM_PATH = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

            # Build a minimal fake release extract tree
            $fakeExtract = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
                -ChildPath ("millennium-fake-extract-" + [guid]::NewGuid().ToString("n"))
            $fakeWinDir  = Join-Path -Path $fakeExtract -ChildPath "scripts\windows"
            New-Item -Path $fakeWinDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path -Path $fakeWinDir -ChildPath "millennium-diag.ps1") -Value "# fake"

            $env:DIAG_TEST_RELEASE_EXTRACT = $fakeExtract
            $env:DIAG_TEST_INSTALL_METHOD  = "manual"
            $env:DIAG_TEST_BYPASS_CHECKS   = "true"

            $script:_fakeExtractPath = $fakeExtract
        }
        AfterAll {
            $env:DIAG_TEST_STEAM_PATH      = $null
            $env:DIAG_TEST_RELEASE_EXTRACT = $null
            $env:DIAG_TEST_INSTALL_METHOD  = $null
            $env:DIAG_TEST_BYPASS_CHECKS   = $null
            if ($script:_fakeExtractPath -and (Test-Path -Path $script:_fakeExtractPath)) {
                Remove-Item -Path $script:_fakeExtractPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "JSON output shows install_method=manual even with a fake release extract" {
            $diagScript = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = & $diagScript -Json -DryRun | ConvertFrom-Json
            $out.install_method     | Should -Be "manual"
            $out.scripts_up_to_date | Should -Be $true
        }
    }
}
