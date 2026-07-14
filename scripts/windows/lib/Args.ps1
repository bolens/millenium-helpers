# Args.ps1 - GNU-style argv parsing, channel validation, typo suggestions


# Apply GNU-style flags from unbound $args (e.g. --json, --yes) onto script switches.
# Target keys may include booleans (Json, Yes, ...) and string values (Channel, File, Rollback).
function Apply-GnuStyleArgs {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$InputArgs,
        [hashtable]$Target
    )
    $remaining = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $InputArgs.Count; $i++) {
        $tok = $InputArgs[$i]
        switch -Regex ($tok) {
            '^--json$' { if ($Target.ContainsKey('Json')) { $Target['Json'] = $true } else { $remaining.Add($tok) } }
            '^(--dry-run|-d)$' { if ($Target.ContainsKey('DryRun')) { $Target['DryRun'] = $true } else { $remaining.Add($tok) } }
            '^(--yes|-y)$' { if ($Target.ContainsKey('Yes')) { $Target['Yes'] = $true } else { $remaining.Add($tok) } }
            '^(--quiet|-q)$' {
                if ($Target.ContainsKey('Quiet')) { $Target['Quiet'] = $true }
                $global:Quiet = $true
                $env:MILLENNIUM_QUIET = "1"
            }
            '^(--help|-h)$' { if ($Target.ContainsKey('Help')) { $Target['Help'] = $true } else { $remaining.Add($tok) } }
            '^(--version|-V)$' { if ($Target.ContainsKey('Version')) { $Target['Version'] = $true } else { $remaining.Add($tok) } }
            '^(--all|-a)$' { if ($Target.ContainsKey('All')) { $Target['All'] = $true } else { $remaining.Add($tok) } }
            '^(--force|-f)$' { if ($Target.ContainsKey('Force')) { $Target['Force'] = $true } else { $remaining.Add($tok) } }
            '^(--skip-theme|-s)$' { if ($Target.ContainsKey('SkipTheme')) { $Target['SkipTheme'] = $true } else { $remaining.Add($tok) } }
            '^--stable$' { if ($Target.ContainsKey('Channel')) { $Target['Channel'] = 'stable' } else { $remaining.Add($tok) } }
            '^--beta$' { if ($Target.ContainsKey('Channel')) { $Target['Channel'] = 'beta' } else { $remaining.Add($tok) } }
            '^--main$' { if ($Target.ContainsKey('Channel')) { $Target['Channel'] = 'main' } else { $remaining.Add($tok) } }
            '^(--channel|-c)$' {
                if ($Target.ContainsKey('Channel') -and ($i + 1) -lt $InputArgs.Count) {
                    $i++
                    $Target['Channel'] = $InputArgs[$i]
                } else {
                    $remaining.Add($tok)
                }
            }
            '^--file$' {
                if ($Target.ContainsKey('File') -and ($i + 1) -lt $InputArgs.Count) {
                    $i++
                    $Target['File'] = $InputArgs[$i]
                } else {
                    $remaining.Add($tok)
                }
            }
            '^(--rollback|-r)$' {
                if ($Target.ContainsKey('Rollback') -and ($i + 1) -lt $InputArgs.Count) {
                    $i++
                    $Target['Rollback'] = $InputArgs[$i]
                } else {
                    $remaining.Add($tok)
                }
            }
            default { $remaining.Add($tok) }
        }
    }
    return $remaining.ToArray()
}


function Get-ClosestToken {
    param(
        [string]$InputToken,
        [string[]]$Candidates
    )
    if ([string]::IsNullOrEmpty($InputToken)) { return $null }
    $best = $null
    $bestScore = 0
    foreach ($c in $Candidates) {
        $score = 0
        if ($c -eq $InputToken) { return $c }
        if ($c.StartsWith($InputToken) -or $InputToken.StartsWith($c)) {
            $score = 4
        } elseif ($c.Contains($InputToken) -or $InputToken.Contains($c)) {
            $score = 3
        } else {
            # Count identical leading characters (e.g. "upg" vs "upgrade" -> 3).
            $i = 0
            while ($i -lt $c.Length -and $i -lt $InputToken.Length -and $c[$i] -eq $InputToken[$i]) {
                $i++
            }
            $score = $i
            # Subsequence: every input char appears in order in candidate (skip gaps).
            # Require Length -ge 2 so a lone letter does not match every command.
            if ($InputToken.Length -ge 2) {
                $ni = 0
                $hi = 0
                while ($ni -lt $InputToken.Length -and $hi -lt $c.Length) {
                    if ($InputToken[$ni] -eq $c[$hi]) { $ni++ }
                    $hi++
                }
                if ($ni -eq $InputToken.Length) {
                    # Prefer closer lengths: "lst"/"list" beats "lst"/"listall".
                    $lenDiff = [Math]::Abs($c.Length - $InputToken.Length)
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


function Test-ValidUpdateChannel {
    param([string]$Channel)
    return ($Channel -eq 'stable' -or $Channel -eq 'beta' -or $Channel -eq 'main')
}


function Require-UpdateChannel {
    param(
        [string]$Channel,
        [string]$Default = 'stable'
    )
    if ([string]::IsNullOrWhiteSpace($Channel)) {
        $Channel = $Default
    }
    if (-not (Test-ValidUpdateChannel -Channel $Channel)) {
        throw "Invalid update channel '$Channel'. Must be 'stable', 'beta', or 'main'."
    }
    return $Channel
}
