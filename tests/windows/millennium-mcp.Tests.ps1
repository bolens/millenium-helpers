Describe "MCP Server Helper" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $goBin = Join-Path $repoRoot "bin\millennium.exe"
        if (-not (Test-Path $goBin)) {
            $goBin = Join-Path $repoRoot "bin\millennium"
        }
        if (-not (Test-Path $goBin)) {
            Push-Location $repoRoot
            try { & make build | Out-Null } finally { Pop-Location }
        }
        if (-not (Test-Path $goBin)) {
            # Linux CI often builds without .exe suffix
            $goBin = Join-Path $repoRoot "bin\millennium"
        }
        $script:GoBin = $goBin
    }

    It "tools/list includes purge confirm and dry_run" {
        if (-not (Test-Path -LiteralPath $script:GoBin)) {
            Set-ItResult -Skipped -Because "Go binary not built"
            return
        }
        $req = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
        $out = $req | & $script:GoBin mcp 2>$null
        $out | Should -BeLike "*millennium_purge*"
        $out | Should -BeLike "*confirm*"
        $out | Should -BeLike "*dry_run*"
    }

    It "millennium_purge without confirm returns isError" {
        if (-not (Test-Path -LiteralPath $script:GoBin)) {
            Set-ItResult -Skipped -Because "Go binary not built"
            return
        }
        $req = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"millennium_purge","arguments":{}}}'
        $out = $req | & $script:GoBin mcp 2>$null
        $out | Should -BeLike "*isError*"
        $out | Should -BeLike "*confirm*"
    }
}
