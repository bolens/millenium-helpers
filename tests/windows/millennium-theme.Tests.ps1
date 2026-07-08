# Pester tests for Windows theme script
$scriptDir = Split-Path -Parent $MyInvocation.ScriptName
$winScriptDir = Join-Path -Path $scriptDir -ChildPath "..\..\scripts\windows"

# Dot-source the common module with dry-run forced
$global:DryRun = $true
. (Join-Path -Path $winScriptDir -ChildPath "common.ps1")

Describe "Theme CLI Manager" {
    Context "Traversal and formatting validation" {
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }

        It "Rejects install arguments that contain path traversal patterns" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$themeScript`" install `"x/../../tmp/evil`"" -PassThru -Wait -NoNewWindow
            $proc.ExitCode | Should -Not -Be 0
        }

        It "Rejects install arguments that contain Windows path traversal patterns" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$themeScript`" install `"x\..\..\tmp\evil`"" -PassThru -Wait -NoNewWindow
            $proc.ExitCode | Should -Not -Be 0
        }

        It "Rejects install arguments without owner/repo format" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$themeScript`" install `"solotheme`"" -PassThru -Wait -NoNewWindow
            $proc.ExitCode | Should -Not -Be 0
        }
    }

    Context "Theme installation standardization" {
        Mock Get-ItemProperty { return [pscustomobject]@{ SteamPath = "C:\MockedSteam" } }
        Mock Test-Path { return $true }
        Mock Invoke-RestMethod { return @( [pscustomobject]@{ sha = "mockcommitsha" } ) }

        It "Accepts owner\repo format and standardizes it to owner/repo" {
            $themeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-theme.ps1"
            # Dry run with backslashes
            $out = & $themeScript install "mockowner\mockrepo" -DryRun
            $out | Should -Contain "Resolving latest commit for mockowner/mockrepo"
        }
    }
}
