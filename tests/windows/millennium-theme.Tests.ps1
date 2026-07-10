Describe "Theme CLI Manager" {
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
            if ($Path -like "*config.json*") {
                return '{"update_channel":"stable","github_token":""}'
            }
            return "3.0.0"
        }
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
    }

    Context "Help and Version" {
        It "Prints usage with -Help" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $out = (& $themeScript -Help *>&1) | Out-String
            $out | Should -BeLike "*Usage:*"
            $out | Should -BeLike "*list*"
            $out | Should -BeLike "*install*"
            $out | Should -BeLike "*SteamClientHomebrew/millennium-steam-skin*"
            $out | Should -BeLike "*-Yes*"
            $out | Should -BeLike "*-Json*"
            $out | Should -BeLike "*GNU-style*"
        }

        It "Prints version with -Version" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $out = (& $themeScript -Version *>&1) | Out-String
            $out | Should -BeLike "*millennium-theme*"
        }

        It "Suggests closest command on typo" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $out = (& $themeScript lst *>&1) | Out-String
            $out | Should -BeLike "*Unknown command*"
            $out | Should -BeLike "*Did you mean*list*"
        }
    }

    Context "Active theme marker" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            $skins = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("mh-skins-" + [guid]::NewGuid().ToString("n"))
            New-Item -ItemType Directory -Path (Join-Path $skins "CoolTheme") -Force | Out-Null
            $themeFull = Join-Path $skins "CoolTheme"
            Mock Test-Path { return $true }
            Mock Get-ChildItem {
                [pscustomobject]@{
                    Name = "CoolTheme"
                    FullName = $themeFull
                    PSIsContainer = $true
                }
            }
            Mock Get-Content {
                if ($Path -like "*config.json*") {
                    return '{"themes":{"activeTheme":"CoolTheme"}}'
                }
                if ($Path -like "*VERSION*") { return "2.2.1" }
                return "{}"
            }
        }

        It "Marks the active theme in list output" {
            $prevApp = $env:APPDATA
            $prevLocal = $env:LOCALAPPDATA
            try {
                $env:APPDATA = Join-Path ([System.IO.Path]::GetTempPath()) "mh-appdata"
                $env:LOCALAPPDATA = Join-Path ([System.IO.Path]::GetTempPath()) "mh-localappdata"
                New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
                $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
                $out = (& $themeScript list *>&1) | Out-String
                $out | Should -BeLike "*CoolTheme*"
                $out | Should -BeLike "*[Active]*"
            } finally {
                $env:APPDATA = $prevApp
                $env:LOCALAPPDATA = $prevLocal
            }
        }
    }

    Context "Empty list UX" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path {
                if ($Path -like "*skins*") { return $false }
                return $true
            }
        }

        It "Suggests an install example when no themes directory exists" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $out = (& $themeScript list *>&1) | Out-String
            $out | Should -BeLike "*millennium theme install*"
        }
    }

    Context "Traversal and formatting validation" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path { return $true }
        }

        It "Rejects install arguments that contain path traversal patterns" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $proc = Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$themeScript`" install `"x/../../tmp/evil`"" -PassThru -Wait -NoNewWindow
            $proc.ExitCode | Should -Not -Be 0
        }

        It "Rejects install arguments that contain Windows path traversal patterns" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $proc = Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$themeScript`" install `"x\..\..\tmp\evil`"" -PassThru -Wait -NoNewWindow
            $proc.ExitCode | Should -Not -Be 0
        }

        It "Rejects install arguments without owner/repo format" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $proc = Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$themeScript`" install `"solotheme`"" -PassThru -Wait -NoNewWindow
            $proc.ExitCode | Should -Not -Be 0
        }
    }

    Context "Theme installation standardization" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path {
                if ($Path -like "*skins*") { return $false }
                return $true
            }
            Mock Invoke-RestMethod { return @( [pscustomobject]@{ sha = "mockcommitsha" } ) }
        }

        It "Accepts owner\repo format and standardizes it to owner/repo" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            # Dry run with backslashes
            $out = (& $themeScript install "mockowner\mockrepo" -DryRun *>&1) | Out-String
            $out | Should -BeLike "*Resolving latest commit for mockowner/mockrepo*"
        }
    }
}
