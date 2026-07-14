Describe "Diag Script" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
        $binDir = Join-Path $repoRoot "bin"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        $outExe = Join-Path $binDir "millennium.exe"
        if (-not (Test-Path -LiteralPath $outExe)) {
            $go = Get-Command go -ErrorAction SilentlyContinue
            if (-not $go) { throw "Go toolchain required for diag thin-wrap tests" }
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
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
    }

    Context "Help and Version" {
        It "Prints usage with -Help" {
            $script = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $script -Help *>&1) | Out-String
            $out | Should -BeLike "*Usage:*"
            $out | Should -BeLike "*doctor*"
        }

        It "Prints version with -Version" {
            $script = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $script -Version *>&1) | Out-String
            $out | Should -BeLike "*millennium-diag*"
        }
    }

    Context "Report via Go" {
        It "Emits diagnostics report and JSON fields" {
            $script = Join-Path -Path $winScriptDir -ChildPath "millennium-diag.ps1"
            $out = (& $script *>&1) | Out-String
            $out | Should -BeLike "*Millennium Diagnostics Report*"
            $json = (& $script --json *>&1) | Out-String
            $json | Should -BeLike "*steam_running*"
            $doctor = (& $script doctor --dry-run *>&1) | Out-String
            $doctor | Should -BeLike "*DRY RUN*"
        }
    }
}
