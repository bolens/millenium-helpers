Describe "Common Helpers" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $global:DryRun = $true
        $global:Quiet = $false
        Remove-Item Env:MILLENNIUM_QUIET -ErrorAction SilentlyContinue
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
    }

    Context "Logging and Args" {
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

    Context "Get-ClosestToken" {
        It "Maps lst to list via subsequence" {
            Get-ClosestToken -InputToken "lst" -Candidates @("list", "install") | Should -Be "list"
        }

        It "Maps stauts to status" {
            Get-ClosestToken -InputToken "stauts" -Candidates @("status", "setup") | Should -Be "status"
        }

        It "Returns null for unrelated input" {
            Get-ClosestToken -InputToken "zzz" -Candidates @("list", "status") | Should -BeNullOrEmpty
        }
    }

    Context "Protect-HelpersConfigFile" {
        It "No-ops when the config file is missing" {
            $missing = Join-Path $TestDrive "missing-config.json"
            { Protect-HelpersConfigFile -Path $missing } | Should -Not -Throw
        }

        It "Locks down ACL inheritance on Windows" {
            if (-not $IsWindows) {
                Set-ItResult -Skipped -Because "Windows ACLs only"
                return
            }
            $cfg = Join-Path $TestDrive "config.json"
            Set-Content -LiteralPath $cfg -Value '{}'
            Protect-HelpersConfigFile -Path $cfg
            $acl = Get-Acl -LiteralPath $cfg
            $acl.AreAccessRulesProtected | Should -Be $true
        }
    }
}
