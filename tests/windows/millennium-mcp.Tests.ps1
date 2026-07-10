Describe "MCP Server Helper" {
    BeforeAll {
        $global:DryRun = $true
    }

    It "Resolves script paths correctly under both installed flat layout and repository layout" {
        $mcpScript = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\millennium-mcp.py"

        # Determine python command
        $pythonCmd = "python3"
        if ($IsWindows) {
            $pythonCmd = "python"
        }

        # 1. Test repository layout resolution (Windows mode forced)
        $resolvedRepo = & $pythonCmd -c "import sys, importlib.util; spec = importlib.util.spec_from_file_location('mcp', sys.argv[1]); mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.IS_WINDOWS = True; print(mod.find_executable('millennium-diag') or '')" $mcpScript
        $resolvedRepo = $resolvedRepo.Trim()
        $resolvedRepo | Should -Not -BeNullOrEmpty
        ($resolvedRepo -replace '\\', '/') | Should -BeLike "*/windows/millennium-diag.ps1"

        # 2. Test installed flat layout resolution (Windows mode forced)
        $tempBin = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "mcp_test_bin"
        New-Item -ItemType Directory -Path $tempBin -Force | Out-Null
        try {
            # Copy mcp.py and a dummy millennium-diag.ps1 to the same flat directory
            $flatMcp = Join-Path -Path $tempBin -ChildPath "millennium-mcp.py"
            Copy-Item -Path $mcpScript -Destination $flatMcp

            $flatDiag = Join-Path -Path $tempBin -ChildPath "millennium-diag.ps1"
            New-Item -ItemType File -Path $flatDiag -Value "exit 0" -Force | Out-Null

            $resolvedFlat = & $pythonCmd -c "import sys, importlib.util; spec = importlib.util.spec_from_file_location('mcp', sys.argv[1]); mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.IS_WINDOWS = True; print(mod.find_executable('millennium-diag') or '')" $flatMcp
            $resolvedFlat = $resolvedFlat.Trim()
            $resolvedFlat | Should -Not -BeNullOrEmpty
            ($resolvedFlat -replace '\\', '/') | Should -Not -BeLike "*/windows/*"
            ($resolvedFlat -replace '\\', '/') | Should -Be ($flatDiag -replace '\\', '/')
        } finally {
            Remove-Item -Path $tempBin -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    It "Requires confirm=true for millennium_purge and supports dry_run" {
        $mcpScript = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts\millennium-mcp.py"
        $pythonCmd = if ($IsWindows) { "python" } else { "python3" }

        $reject = & $pythonCmd -c @"
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('mcp', sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
result = mod.handle_tool_call('millennium_purge', {})
print(json.dumps(result))
"@ $mcpScript
        $rejectObj = $reject | ConvertFrom-Json
        $rejectObj.isError | Should -Be $true
        ($rejectObj.content[0].text) | Should -BeLike "*confirm=true*"

        $tools = & $pythonCmd -c @"
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('mcp', sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(json.dumps(mod.get_tools_list()))
"@ $mcpScript
        $tools | Should -BeLike "*confirm*"
        $tools | Should -BeLike "*dry_run*"
    }
}
