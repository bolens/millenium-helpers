Describe "Windows millennium install bootstrap (Go)" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
        $binDir = Join-Path $repoRoot "bin"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        $outExe = Join-Path $binDir "millennium.exe"
        $go = Get-Command go -ErrorAction SilentlyContinue
        if (-not $go) { throw "Go toolchain required for install tests" }
        $ver = [System.IO.File]::ReadAllText((Join-Path $repoRoot "VERSION")).Trim()
        # Always rebuild so help/flags match the working tree (stale bin/millennium.exe breaks assertions).
        Push-Location (Join-Path $repoRoot "go")
        try {
            & go build "-ldflags=-X github.com/bolens/millenium-helpers/internal/version.Version=$ver" `
                -o $outExe ./cmd/millennium
            if ($LASTEXITCODE -ne 0) { throw "go build failed" }
        } finally {
            Pop-Location
        }
        $script:exe = $outExe
    }

    It "millennium install --help documents track" {
        $out = (& $script:exe install --help *>&1) | Out-String
        $out | Should -BeLike "*millennium install*"
        $out | Should -BeLike "*--track*"
    }

    It "millennium uninstall --help documents purge" {
        $out = (& $script:exe uninstall --help *>&1) | Out-String
        $out | Should -BeLike "*millennium uninstall*"
        $out | Should -BeLike "*--purge*"
    }
}
