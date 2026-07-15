Describe "Upgrade Script" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
        $binDir = Join-Path $repoRoot "bin"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        $outExe = Join-Path $binDir "millennium.exe"
        if (-not (Test-Path -LiteralPath $outExe)) {
            $go = Get-Command go -ErrorAction SilentlyContinue
            if (-not $go) { throw "Go toolchain required for upgrade thin-wrap tests" }
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
    }

    Context "Help and Version" {
        It "Prints usage with -Help" {
            $script = Join-Path -Path $winScriptDir -ChildPath "millennium-upgrade.ps1"
            $out = (& $script -Help *>&1) | Out-String
            $out | Should -BeLike "*Usage:*"
            $out | Should -BeLike "*channel*"
        }

        It "Prints version with -Version" {
            $script = Join-Path -Path $winScriptDir -ChildPath "millennium-upgrade.ps1"
            $out = (& $script -Version *>&1) | Out-String
            $out | Should -BeLike "*millennium-upgrade*"
        }
    }
}
