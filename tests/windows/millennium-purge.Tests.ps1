Describe "Purge Script" {
    BeforeAll {
        $winScriptDir = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\windows"
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
        $binDir = Join-Path $repoRoot "bin"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        $outExe = Join-Path $binDir "millennium.exe"
        if (-not (Test-Path -LiteralPath $outExe)) {
            $go = Get-Command go -ErrorAction SilentlyContinue
            if (-not $go) { throw "Go toolchain required for purge thin-wrap tests" }
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
        $global:DryRun = $true
        if (!$IsWindows) {
            New-PSDrive -Name HKCU -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
            New-PSDrive -Name C -PSProvider FileSystem -Root ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Out-Null
        }
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

    Context "Dry-run via Go" {
        It "Announces dry-run and completes" {
            $purgeScript = Join-Path -Path $winScriptDir -ChildPath "millennium-purge.ps1"
            $out = (& $purgeScript -DryRun -Yes *>&1) | Out-String
            $out | Should -BeLike "*DRY RUN*"
            $out | Should -BeLike "*completed successfully*"
            $out | Should -Not -BeLike "*Are you sure*"
        }
    }
}
