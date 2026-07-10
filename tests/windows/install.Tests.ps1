Describe "Windows Installer" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        $env:PSTESTS = "true"
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

            $expectedScripts = @(
                "common.ps1",
                "millennium.ps1",
                "millennium-diag.ps1",
                "millennium-purge.ps1",
                "millennium-repair.ps1",
                "millennium-schedule.ps1",
                "millennium-theme.ps1",
                "millennium-upgrade.ps1"
            )
            foreach ($script in $expectedScripts) {
                Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath $script) | Should -Be $true
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

            Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath "millennium-mcp.ps1") | Should -Be $true
            Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath "millennium-mcp.py") | Should -Be $true

            $installOut | Should -BeLike "*Getting started*"
            $installOut | Should -BeLike "*millennium diag*"
            $installOut | Should -BeLike "*millennium upgrade*"
            $installOut | Should -BeLike "*Long names*"

            # 2. Run Uninstall
            & $installScript -Uninstall

            # Verify clean up
            Test-Path -Path $expectedInstallDir | Should -Be $false

        } finally {
            # Restore USERPROFILE
            $env:USERPROFILE = $oldUserProfile
            Remove-Item -Path $tempHome -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Context "Standalone / Piped Installer Mode" {
        BeforeAll {
            Mock Invoke-WebRequest {
                param($Uri, $OutFile, $UseBasicParsing)
                New-Item -Path $OutFile -ItemType File -Force | Out-Null
            }
            Mock Expand-Archive {
                param($Path, $DestinationPath, $Force)
                $repoRoot = Join-Path -Path $PSScriptRoot -ChildPath "..\.."
                $targetExtractDir = Join-Path -Path $DestinationPath -ChildPath "millenium-helpers-main"
                New-Item -Path $targetExtractDir -ItemType Directory -Force | Out-Null
                $extractedWinDir = Join-Path -Path $targetExtractDir -ChildPath "scripts\windows"
                New-Item -Path $extractedWinDir -ItemType Directory -Force | Out-Null
                $mockInstallPs1 = Join-Path -Path $extractedWinDir -ChildPath "install.ps1"
                "Write-Host 'Mock installer executed successfully'" | Set-Content -Path $mockInstallPs1 -Force
            }
        }

        It "Detects standalone mode and successfully delegates to extracted repository installer" {
            $installScript = Join-Path -Path $winScriptDir -ChildPath "install.ps1"
            $sb = [scriptblock]::Create((Get-Content $installScript -Raw))
            
            $out = (& $sb *>&1) | Out-String
            $out | Should -BeLike "*Running in standalone/piped mode. Downloading repository*"
            $out | Should -BeLike "*Mock installer executed successfully*"
        }
    }
}
