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
