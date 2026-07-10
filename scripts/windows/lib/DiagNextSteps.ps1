# DiagNextSteps.ps1 - Prioritized next-steps footer for the diagnostics report

function Print-PackageUpgradeHint {
    switch ($script:InstallMethod) {
        'scoop'  { Write-Host '  scoop update millennium-helpers' }
        'winget' { Write-Host '  winget upgrade bolens.millenniumhelpers' }
        'manual' { Write-Host '  millennium doctor                 # sync scripts for current helpers track' }
        'mixed'  { Write-Host '  Resolve mixed install, then re-run: millennium doctor' }
        default  { Write-Host '  millennium doctor' }
    }
}

function Print-DiagNextSteps {
    $issues      = 0
    $suggestions = [System.Collections.Generic.List[string]]::new()

    # Priority 1: mixed install blocks everything else
    if ($script:InstallMethod -eq 'mixed') {
        $issues++
        $suggestions.Add('Resolve mixed install (scoop/winget/manual conflict) - remove duplicates first')
    }

    # Priority 2: helper scripts outdated
    if (!$script:ScriptsUpToDate) {
        $issues++
        switch ($script:InstallMethod) {
            'scoop'  { $suggestions.Add('scoop update millennium-helpers           # update helper scripts') }
            'winget' { $suggestions.Add('winget upgrade bolens.millenniumhelpers   # update helper scripts') }
            default  { $suggestions.Add('millennium doctor                          # sync scripts for current helpers track') }
        }
    }

    # Priority 3: obsolete files
    if (!$script:CleanOfObsolete) {
        $issues++
        $suggestions.Add('millennium doctor                          # remove legacy wrapper files')
    }

    # Priority 4: Millennium binaries
    if (!$script:BinariesOk) {
        $issues++
        $suggestions.Add('millennium upgrade -Force                  # repair/reinstall Millennium binaries')
    }

    # Priority 5: Steam folder permissions
    if (!$script:PermissionsOk) {
        $issues++
        $suggestions.Add('millennium repair                          # fix Steam folder permissions')
    }

    # Priority 6: missing skins dir
    if (!$script:SkinsDirOk) {
        $issues++
        $suggestions.Add('millennium doctor                          # create missing skins directory')
    }

    # Priority 7: missing scheduled task
    if (!$script:TaskOk) {
        $issues++
        $suggestions.Add('millennium schedule enable                 # enable daily auto-updates')
    }

    # Priority 8: PowerShell completions
    if (!$script:CompletionsOk) {
        $issues++
        $suggestions.Add('millennium doctor                          # repair PowerShell completions')
    }

    Write-Host ''
    if ($issues -eq 0) {
        Write-Host -ForegroundColor Green 'No issues detected. Your Millennium installation looks healthy.'
        Write-Host "Tip: run 'millennium schedule status' to review auto-updates, or 'millennium theme list' for skins."
        return
    }

    Write-Host -ForegroundColor Yellow "$issues issue(s) detected. Suggested next steps:"
    $seen = @{}
    foreach ($s in $suggestions) {
        if ($seen.ContainsKey($s)) { continue }
        $seen[$s] = $true
        Write-Host "  * $s"
    }
    Write-Host ''
    Write-Host "Or run 'millennium doctor' to attempt automatic repairs."
}
