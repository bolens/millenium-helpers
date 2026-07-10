Describe "Purge Script" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        function Stop-Process { }
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name C -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
        }
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
    }

    Context "Help and Version" {
        It "Prints usage with -Help" {
            $purgeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-purge.ps1"
            $out = (& $purgeScript -Help *>&1) | Out-String
            $out | Should -BeLike "*Usage:*"
            $out | Should -BeLike "*-Yes*"
        }

        It "Prints version with -Version" {
            $purgeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-purge.ps1"
            $out = (& $purgeScript -Version *>&1) | Out-String
            $out | Should -BeLike "*millennium-purge*"
            $out | Should -Match "\d+\.\d+\.\d+|unknown"
        }
    }

    Context "Confirmation" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path { return $true }
            Mock Get-Process { return $null }
            Mock Test-Admin { return $true }
        }

        It "Accepts -Yes with -DryRun to skip confirmation" {
            $purgeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-purge.ps1"
            $out = (& $purgeScript -DryRun -Yes *>&1) | Out-String
            $out | Should -BeLike "*Initiating Millennium Purge*"
            $out | Should -BeLike "*completed successfully*"
            $out | Should -Not -BeLike "*Are you sure*"
        }
    }

    Context "Purge Execution" {
        BeforeAll {
            Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
            Mock Test-Path { return $true }
            Mock Get-Process { return $null }
            Mock Test-Admin { return $true }
        }

        It "Runs the client purge uninstallation logic without errors" {
            $purgeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-purge.ps1"
            $out = (& $purgeScript -DryRun *>&1) | Out-String
            $out | Should -BeLike "*Initiating Millennium Purge (Uninstall)*"
            $out | Should -BeLike "*Millennium Purge completed successfully.*"
        }
    }
}
