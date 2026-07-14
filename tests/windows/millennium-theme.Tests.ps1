Describe "Theme CLI Manager" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name C -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
        }
        # Phase 6e: list thin-wraps to Go millennium.exe.
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
        $binDir = Join-Path $repoRoot "bin"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        $outExe = Join-Path $binDir "millennium.exe"
        if (-not (Test-Path -LiteralPath $outExe)) {
            $go = Get-Command go -ErrorAction SilentlyContinue
            if (-not $go) {
                throw "Go toolchain required for theme list thin-wrap tests"
            }
            $ver = [System.IO.File]::ReadAllText((Join-Path $repoRoot "VERSION")).Trim()
            Push-Location (Join-Path $repoRoot "go")
            try {
                & go build "-ldflags=-X github.com/bolens/millenium-helpers/internal/version.Version=$ver" `
                    -o $outExe ./cmd/millennium
                if ($LASTEXITCODE -ne 0) { throw "go build failed for millennium.exe" }
            } finally {
                Pop-Location
            }
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
        It "Marks the active theme in list output" {
            $prevApp = $env:APPDATA
            $prevLocal = $env:LOCALAPPDATA
            $prevSkins = $env:MILLENNIUM_SKINS_DIR
            $skins = Join-Path ([System.IO.Path]::GetTempPath()) ("mh-skins-" + [guid]::NewGuid().ToString("n"))
            $appData = Join-Path ([System.IO.Path]::GetTempPath()) ("mh-appdata-" + [guid]::NewGuid().ToString("n"))
            try {
                New-Item -ItemType Directory -Path (Join-Path $skins "CoolTheme") -Force | Out-Null
                $cfgDir = Join-Path $appData "millennium"
                New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
                '{"themes":{"activeTheme":"CoolTheme"}}' |
                    Set-Content -Path (Join-Path $cfgDir "config.json") -Encoding utf8
                $env:APPDATA = $appData
                $env:LOCALAPPDATA = Join-Path ([System.IO.Path]::GetTempPath()) ("mh-local-" + [guid]::NewGuid().ToString("n"))
                $env:MILLENNIUM_SKINS_DIR = $skins
                $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
                $out = (& $themeScript list *>&1) | Out-String
                $out | Should -BeLike "*CoolTheme*"
                $out | Should -BeLike "*[Active]*"
            } finally {
                $env:APPDATA = $prevApp
                $env:LOCALAPPDATA = $prevLocal
                if ($null -eq $prevSkins) {
                    Remove-Item Env:MILLENNIUM_SKINS_DIR -ErrorAction SilentlyContinue
                } else {
                    $env:MILLENNIUM_SKINS_DIR = $prevSkins
                }
                Remove-Item -Path $skins, $appData -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Empty list UX" {
        It "Suggests an install example when no themes directory exists" {
            $prevSkins = $env:MILLENNIUM_SKINS_DIR
            try {
                $env:MILLENNIUM_SKINS_DIR = Join-Path ([System.IO.Path]::GetTempPath()) ("mh-missing-skins-" + [guid]::NewGuid().ToString("n"))
                $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
                $out = (& $themeScript list *>&1) | Out-String
                $out | Should -BeLike "*millennium theme install*"
            } finally {
                if ($null -eq $prevSkins) {
                    Remove-Item Env:MILLENNIUM_SKINS_DIR -ErrorAction SilentlyContinue
                } else {
                    $env:MILLENNIUM_SKINS_DIR = $prevSkins
                }
            }
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
