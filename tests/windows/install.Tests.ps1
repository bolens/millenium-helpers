Describe "Windows Installer" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $repoRoot = Join-Path -Path $PSScriptRoot -ChildPath "..\.."
        $global:DryRun = $true
        $env:PSTESTS = "true"

        # Installer requires millennium.exe (stub or build for the suite).
        $binDir = Join-Path -Path $repoRoot -ChildPath "bin"
        if (!(Test-Path -LiteralPath $binDir)) {
            New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        }
        $outExe = Join-Path -Path $binDir -ChildPath "millennium.exe"
        if (!(Test-Path -LiteralPath $outExe -PathType Leaf)) {
            $goCmd = Get-Command go -ErrorAction SilentlyContinue
            $goMain = Join-Path -Path $repoRoot -ChildPath "go\cmd\millennium"
            if ($goCmd -and (Test-Path -LiteralPath $goMain)) {
                Push-Location (Join-Path -Path $repoRoot -ChildPath "go")
                try {
                    & go build -o $outExe ./cmd/millennium
                    if ($LASTEXITCODE -ne 0) { throw "go build failed for millennium.exe" }
                } finally {
                    Pop-Location
                }
            } else {
                Set-Content -Path $outExe -Value "millennium-stub" -Encoding ASCII
            }
        }
    }

    It "Successfully runs installation and uninstallation routines" {
        $installScript = Join-Path -Path $winScriptDir -ChildPath "install.ps1"
        $tempHome = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "pester_test_home"

        # Override USERPROFILE so installer writes to temp directory
        $oldUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $tempHome

        try {
            # 1. Run Install
            $installOut = (& $installScript *>&1) | Out-String

            # Verify directory and files exist
            $expectedInstallDir = Join-Path -Path $tempHome -ChildPath ".millennium-helpers"
            $expectedBinDir = Join-Path -Path $expectedInstallDir -ChildPath "bin"

            Test-Path -Path $expectedBinDir | Should -Be $true
            Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath "millennium.exe") | Should -Be $true
            $installOut | Should -BeLike "*millennium.exe (Go dispatcher)*"

            Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath "common.ps1") | Should -Be $true
            foreach ($gone in @(
                    "millennium-diag.ps1",
                    "millennium-mcp.ps1",
                    "millennium-purge.ps1",
                    "millennium-repair.ps1",
                    "millennium-schedule.ps1",
                    "millennium-theme.ps1",
                    "millennium-upgrade.ps1"
                )) {
                Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath $gone) | Should -Be $false
            }

            $expectedWrappers = @(
                "millennium.cmd",
                "millennium-diag.cmd",
                "millennium-mcp.cmd",
                "millennium-purge.cmd",
                "millennium-repair.cmd",
                "millennium-schedule.cmd",
                "millennium-theme.cmd",
                "millennium-upgrade.cmd"
            )
            foreach ($wrapper in $expectedWrappers) {
                Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath $wrapper) | Should -Be $true
            }
            (Get-Content -Path (Join-Path -Path $expectedBinDir -ChildPath "millennium.cmd") -Raw) | Should -BeLike "*millennium.exe*"
            (Get-Content -Path (Join-Path -Path $expectedBinDir -ChildPath "millennium-upgrade.cmd") -Raw) | Should -BeLike "*millennium.exe*upgrade*"
            (Get-Content -Path (Join-Path -Path $expectedBinDir -ChildPath "millennium-mcp.cmd") -Raw) | Should -BeLike "*millennium.exe*mcp*"

            Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath "millennium-mcp.py") | Should -Be $false
            Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath "millennium-helpers.completion.ps1") | Should -Be $true

            # Shared Windows libs remain for install/test helpers (Logging, Args, …).
            $expectedLibDir = Join-Path -Path $expectedBinDir -ChildPath "lib"
            Test-Path -Path $expectedLibDir | Should -Be $true
            Test-Path -Path (Join-Path -Path $expectedLibDir -ChildPath "UpgradeRollback.ps1") | Should -Be $false
            Test-Path -Path (Join-Path -Path $expectedLibDir -ChildPath "Download.ps1") | Should -Be $false
            Test-Path -Path (Join-Path -Path $expectedLibDir -ChildPath "Archive.ps1") | Should -Be $false
            Test-Path -Path (Join-Path -Path $expectedLibDir -ChildPath "Logging.ps1") | Should -Be $true
            Test-Path -Path (Join-Path -Path $expectedLibDir -ChildPath "DiagReport.ps1") | Should -Be $false
            Test-Path -Path (Join-Path -Path $expectedLibDir -ChildPath "RepairOps.ps1") | Should -Be $false

            $pwshProfile = Join-Path -Path $tempHome -ChildPath "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
            $winProfile = Join-Path -Path $tempHome -ChildPath "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
            Test-Path -Path $pwshProfile | Should -Be $true
            (Get-Content -Path $pwshProfile -Raw) | Should -BeLike "*millennium-helpers.completion.ps1*"
            Test-Path -Path $winProfile | Should -Be $true
            (Get-Content -Path $winProfile -Raw) | Should -BeLike "*millennium-helpers.completion.ps1*"

            $installOut | Should -BeLike "*Getting started*"
            $installOut | Should -BeLike "*millennium diag*"
            $installOut | Should -BeLike "*millennium upgrade*"
            $installOut | Should -BeLike "*Long names*"

            # Seed scheduled-task cmdlets for uninstall coverage (including non-Windows CI)
            function global:Get-ScheduledTask {
                param($TaskName, $ErrorAction)
                return [pscustomobject]@{ TaskName = "MillenniumUpdate" }
            }
            function global:Unregister-ScheduledTask {
                param($TaskName, $Confirm)
            }

            # 2. Run Uninstall
            $uninstallOut = (& $installScript -Uninstall *>&1) | Out-String

            # Verify clean up
            Test-Path -Path $expectedInstallDir | Should -Be $false
            (Get-Content -Path $pwshProfile -Raw -ErrorAction SilentlyContinue) | Should -Not -BeLike "*millennium-helpers.completion.ps1*"
            (Get-Content -Path $winProfile -Raw -ErrorAction SilentlyContinue) | Should -Not -BeLike "*millennium-helpers.completion.ps1*"
            $uninstallOut | Should -BeLike "*Removed scheduled task: MillenniumUpdate*"

            Remove-Item -Path function:global:Get-ScheduledTask -ErrorAction SilentlyContinue
            Remove-Item -Path function:global:Unregister-ScheduledTask -ErrorAction SilentlyContinue

        } finally {
            # Restore USERPROFILE
            $env:USERPROFILE = $oldUserProfile
            Remove-Item -Path $tempHome -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Context "Standalone / Piped Installer Mode" {
        BeforeAll {
            Mock Invoke-RestMethod {
                param($Uri, $Headers, $UseBasicParsing)
                if ($Uri -like "*api.github.com/*/releases/latest*") {
                    return [pscustomobject]@{ tag_name = 'v2.6.2' }
                }
                throw "Unexpected Invoke-RestMethod URI: $Uri"
            }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile, $UseBasicParsing)
                if (-not $OutFile) { return }
                if ($Uri -like "*.sha256*") {
                    $zipCandidate = $OutFile -replace '\.sha256$', ''
                    if (!(Test-Path -Path $zipCandidate -PathType Leaf)) {
                        $zipCandidate = Join-Path -Path (Split-Path -Parent $OutFile) -ChildPath "millennium-helpers-v2.6.2-windows-amd64.zip"
                    }
                    $hash = (Get-FileHash -Path $zipCandidate -Algorithm SHA256).Hash.ToLowerInvariant()
                    Set-Content -Path $OutFile -Value "$hash  millennium-helpers-v2.6.2-windows-amd64.zip" -Force
                } else {
                    Set-Content -Path $OutFile -Value "fake-zip-content" -Force
                }
            }
            Mock Expand-Archive {
                param($Path, $DestinationPath, $Force)
                # Trimmed release layout: scripts/windows at archive root
                $extractedWinDir = Join-Path -Path $DestinationPath -ChildPath "scripts\windows"
                New-Item -Path $extractedWinDir -ItemType Directory -Force | Out-Null
                $mockInstallPs1 = Join-Path -Path $extractedWinDir -ChildPath "install.ps1"
                "Write-Host 'Mock installer executed successfully'" | Set-Content -Path $mockInstallPs1 -Force
            }
        }

        It "Detects standalone mode and successfully delegates to extracted repository installer" {
            $installScript = Join-Path -Path $winScriptDir -ChildPath "install.ps1"
            $sb = [scriptblock]::Create((Get-Content $installScript -Raw))

            $out = (& $sb *>&1) | Out-String
            $out | Should -BeLike "*Running in standalone/piped mode. Downloading helpers (track=*"
            $out | Should -BeLike "*SHA256 checksum verified*"
            $out | Should -BeLike "*Mock installer executed successfully*"
        }
    }
}
