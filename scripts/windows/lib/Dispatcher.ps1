# Dispatcher.ps1 - Dispatcher helpers for millennium.ps1

function Get-CommandSuggestion {
    param([string]$InputCmd)
    $cmds = @("diag", "doctor", "upgrade", "schedule", "theme", "repair", "purge", "mcp", "help")
    if ([string]::IsNullOrEmpty($InputCmd)) { return $null }
    $best = $null
    $bestScore = 0
    foreach ($c in $cmds) {
        $score = 0
        if ($c -eq $InputCmd) { return $c }
        if ($c.StartsWith($InputCmd) -or $InputCmd.StartsWith($c)) {
            $score = 4
        } elseif ($c.Contains($InputCmd) -or $InputCmd.Contains($c)) {
            $score = 3
        } else {
            # Identical leading characters (e.g. "upg" vs "upgrade" -> 3).
            $i = 0
            while ($i -lt $c.Length -and $i -lt $InputCmd.Length -and $c[$i] -eq $InputCmd[$i]) {
                $i++
            }
            $score = $i
            # Subsequence with gaps; Length -ge 2 avoids matching every command on one letter.
            if ($InputCmd.Length -ge 2) {
                $ni = 0
                $hi = 0
                while ($ni -lt $InputCmd.Length -and $hi -lt $c.Length) {
                    if ($InputCmd[$ni] -eq $c[$hi]) { $ni++ }
                    $hi++
                }
                if ($ni -eq $InputCmd.Length) {
                    $lenDiff = [Math]::Abs($c.Length - $InputCmd.Length)
                    $subScore = 3 - $lenDiff
                    if ($subScore -lt 2) { $subScore = 2 }
                    if ($subScore -gt $score) { $score = $subScore }
                }
            }
        }
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $c
        }
    }
    if ($bestScore -ge 2) { return $best }
    return $null
}

function Invoke-Sibling {
    param(
        [string]$Name,
        [string[]]$ArgsList
    )
    $baseDir = $ScriptDir
    if (-not $baseDir -and $script:MillenniumHelpersWinDir) {
        $baseDir = $script:MillenniumHelpersWinDir
    }
    $scriptPath = Join-Path -Path $baseDir -ChildPath "$Name.ps1"
    if (-not [System.IO.File]::Exists($scriptPath)) {
        $cmd = Get-Command -Name "$Name.ps1" -ErrorAction SilentlyContinue
        if ($cmd) {
            $scriptPath = $cmd.Source
        } else {
            Write-Error "Error: '$Name' not found."
            exit 1
        }
    }
    & $scriptPath @ArgsList
    exit $LASTEXITCODE
}
