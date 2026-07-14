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
        . (Join-Path -Path $winScriptDir -ChildPath "common.ps1")
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

    Context "Dry-run via Go" {
        It "Verifies local archive SHA in dry-run" {
            $script = Join-Path -Path $winScriptDir -ChildPath "millennium-upgrade.ps1"
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mh-up-" + [guid]::NewGuid().ToString("n"))
            New-Item -ItemType Directory -Force -Path $tmp | Out-Null
            $archive = Join-Path $tmp "fake.tgz"
            Set-Content -Path $archive -Value "millennium-archive-body" -NoNewline
            $sha = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
            $out = (& $script -File $archive -Sha256 $sha -DryRun *>&1) | Out-String
            $out | Should -BeLike "*DRY RUN*"
            $out | Should -BeLike "*Verified SHA256*"
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }
}
