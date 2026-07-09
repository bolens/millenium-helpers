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
            & $installScript

            # Verify directory and files exist
            $expectedInstallDir = Join-Path -Path $tempHome -ChildPath ".millennium-helpers"
            $expectedBinDir = Join-Path -Path $expectedInstallDir -ChildPath "bin"

            Test-Path -Path $expectedBinDir | Should -Be $true

            $expectedScripts = @(
                "common.ps1",
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
                "millennium-diag.cmd",
                "millennium-purge.cmd",
                "millennium-repair.cmd",
                "millennium-schedule.cmd",
                "millennium-theme.cmd",
                "millennium-upgrade.cmd"
            )
            foreach ($wrapper in $expectedWrappers) {
                Test-Path -Path (Join-Path -Path $expectedBinDir -ChildPath $wrapper) | Should -Be $true
            }

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
}
