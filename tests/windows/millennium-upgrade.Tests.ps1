# Pester tests for Windows upgrade script
$scriptDir = Split-Path -Parent $MyInvocation.ScriptName
$winScriptDir = Join-Path -Path $scriptDir -ChildPath "..\..\scripts\windows"

# Dot-source the common module with dry-run forced
$global:DryRun = $true
. (Join-Path -Path $winScriptDir -ChildPath "common.ps1")

Describe "Upgrade Script" {
    Context "Upgrade Validation" {
        It "Validates channels successfully" {
            $upgradeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-upgrade.ps1"
            
            # Test invalid channel exits with non-zero
            $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$upgradeScript`" -Channel invalid -DryRun" -PassThru -Wait -NoNewWindow
            $proc.ExitCode | Should -Not -Be 0
        }
    }

    Context "Upgrade Dry-Run" {
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }
        Mock Invoke-RestMethod { return [pscustomobject]@{ tag_name = "v3.3.1" } }

        It "Succeeds dry-run on stable channel upgrade" {
            $upgradeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-upgrade.ps1"
            $out = & $upgradeScript -Channel stable -DryRun
            $out | Should -Contain "Would download"
        }
    }
}
