Describe "Windows millennium install (Go)" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
        $binDir = Join-Path $repoRoot "bin"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        $outExe = Join-Path $binDir "millennium.exe"
        if (-not (Test-Path -LiteralPath $outExe)) {
            $go = Get-Command go -ErrorAction SilentlyContinue
            if (-not $go) { throw "Go toolchain required for install tests" }
            $ver = [System.IO.File]::ReadAllText((Join-Path $repoRoot "VERSION")).Trim()
            Push-Location (Join-Path $repoRoot "go")
            try {
                & go build "-ldflags=-X github.com/bolens/millenium-helpers/internal/version.Version=$ver" `
                    -o $outExe ./cmd/millennium
                if ($LASTEXITCODE -ne 0) { throw "go build failed" }
            } finally {
                Pop-Location
            }
        }
        $env:PSTESTS = "true"
        $script:exe = $outExe
    }

    It "millennium install --help documents track" {
        $out = (& $script:exe install --help *>&1) | Out-String
        $out | Should -BeLike "*millennium install*"
        $out | Should -BeLike "*--track*"
    }

    It "installs into a fixture USERPROFILE prefix" {
        $tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("mh-install-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Force -Path $tempHome | Out-Null
        try {
            $prevProfile = $env:USERPROFILE
            $env:USERPROFILE = $tempHome
            $env:MILLENNIUM_SOURCE_ROOT = "$repoRoot"
            $prefix = Join-Path $tempHome ".millennium-helpers"
            $target = Join-Path $prefix "bin"
            & $script:exe install --prefix $target --skip-wizard
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $target "millennium.exe") | Should -Be $true
            Test-Path -LiteralPath (Join-Path $target "millennium-upgrade.cmd") | Should -Be $false
            Test-Path -LiteralPath (Join-Path $prefix "install-meta.json") | Should -Be $true

            & $script:exe uninstall --prefix $target
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $target "millennium.exe") | Should -Be $false
        } finally {
            $env:USERPROFILE = $prevProfile
            Remove-Item -Recurse -Force -LiteralPath $tempHome -ErrorAction SilentlyContinue
        }
    }
}
