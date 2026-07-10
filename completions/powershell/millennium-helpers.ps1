# PowerShell argument completers for Millennium Helpers.
# Dot-source from your profile, or let install.ps1 register a profile hook:
#   . "$HOME/.millennium-helpers/bin/millennium-helpers.completion.ps1"

Set-StrictMode -Version Latest

function Global:Get-MillenniumDispatcherCommands {
    @('diag', 'doctor', 'upgrade', 'schedule', 'theme', 'repair', 'purge', 'mcp', 'help')
}

function Global:Get-MillenniumScheduleActions {
    @('enable', 'disable', 'status', 'setup', 'config')
}

function Global:Get-MillenniumScheduleChannels {
    @('stable', 'beta', 'main')
}

function Global:Get-MillenniumConfigActions {
    @('get', 'set', 'list')
}

function Global:Get-MillenniumDiagActions {
    @('doctor', 'logs', '--fix')
}

function Global:Get-MillenniumThemeActions {
    @('list', 'install', 'remove', 'update')
}

function script:Filter-Completions {
    param(
        [string[]]$Candidates,
        [string]$WordToComplete
    )
    if ([string]::IsNullOrEmpty($WordToComplete)) {
        return @($Candidates)
    }
    return @($Candidates | Where-Object { $_ -like "$WordToComplete*" })
}

function script:New-CompletionResult {
    param([string]$Value, [string]$ToolTip = $Value)
    [System.Management.Automation.CompletionResult]::new(
        $Value,
        $Value,
        'ParameterValue',
        $ToolTip
    )
}

function Global:Complete-MillenniumNative {
    param(
        [string]$CommandName,
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $elements = @($CommandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    # Drop the command name itself
    $args = @()
    if ($elements.Count -gt 1) {
        $args = @($elements[1..($elements.Count - 1)])
    }

    # If the cursor is still on a partial token, exclude it from prior-args.
    if ($args.Count -gt 0 -and -not [string]::IsNullOrEmpty($WordToComplete) -and $args[-1] -eq $WordToComplete) {
        if ($args.Count -eq 1) {
            $args = @()
        } else {
            $args = @($args[0..($args.Count - 2)])
        }
    }

    $candidates = @()

    switch -Regex ($CommandName) {
        '^millennium$' {
            if ($args.Count -eq 0) {
                $candidates = Get-MillenniumDispatcherCommands
            } else {
                switch ($args[0]) {
                    { $_ -in @('diag', 'doctor') } {
                        if ($args.Count -eq 1) {
                            $candidates = Get-MillenniumDiagActions
                        } else {
                            $candidates = @('--json', '--fix', '-f', '--force', '--follow', '-l', '--yes', '-y', '--share', '-s', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
                        }
                    }
                    'upgrade' {
                        $candidates = @('--channel', '-c', '--stable', '--beta', '--main', '--rollback', '-r', '--file', '--force', '-f', '--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
                        if ($args.Count -ge 2 -and $args[-1] -in @('--channel', '-c')) {
                            $candidates = Get-MillenniumScheduleChannels
                        }
                    }
                    'schedule' {
                        if ($args.Count -eq 1) {
                            $candidates = Get-MillenniumScheduleActions
                        } elseif ($args.Count -eq 2 -and $args[1] -eq 'enable') {
                            $candidates = Get-MillenniumScheduleChannels
                        } elseif ($args.Count -eq 2 -and $args[1] -eq 'config') {
                            $candidates = Get-MillenniumConfigActions
                        } else {
                            $candidates = @('--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
                        }
                    }
                    'theme' {
                        if ($args.Count -eq 1) {
                            $candidates = Get-MillenniumThemeActions
                        } else {
                            $candidates = @('--all', '-a', '--json', '--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
                        }
                    }
                    'repair' {
                        $candidates = @('--skip-theme', '-s', '--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
                    }
                    'purge' {
                        $candidates = @('--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
                    }
                    'mcp' {
                        $candidates = @('--register', '-r', '--version', '-V', '--help', '-h')
                    }
                }
            }
        }
        '^millennium-schedule$' {
            if ($args.Count -eq 0) {
                $candidates = @(Get-MillenniumScheduleActions) + @('--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
            } elseif ($args.Count -eq 1 -and $args[0] -eq 'enable') {
                $candidates = Get-MillenniumScheduleChannels
            } elseif ($args.Count -eq 1 -and $args[0] -eq 'config') {
                $candidates = Get-MillenniumConfigActions
            } else {
                $candidates = @('--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
            }
        }
        '^millennium-diag$' {
            if ($args.Count -eq 0) {
                $candidates = @(Get-MillenniumDiagActions) + @('--force', '--json', '--follow', '-l', '--yes', '-y', '--share', '-s', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
            } else {
                $candidates = @('--force', '--json', '--follow', '-l', '--yes', '-y', '--share', '-s', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
            }
        }
        '^millennium-upgrade$' {
            if ($args.Count -ge 1 -and $args[-1] -in @('--channel', '-c')) {
                $candidates = Get-MillenniumScheduleChannels
            } else {
                $candidates = @('--channel', '-c', '--stable', '--beta', '--main', '--rollback', '-r', '--file', '--force', '-f', '--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
            }
        }
        '^millennium-theme$' {
            if ($args.Count -eq 0) {
                $candidates = @(Get-MillenniumThemeActions) + @('--json', '--all', '-a', '--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
            } else {
                $candidates = @('--json', '--all', '-a', '--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
            }
        }
        '^millennium-repair$' {
            $candidates = @('--skip-theme', '-s', '--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
        }
        '^millennium-purge$' {
            $candidates = @('--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
        }
        '^millennium-mcp$' {
            $candidates = @('--register', '-r', '--version', '-V', '--help', '-h')
        }
    }

    $filtered = Filter-Completions -Candidates $candidates -WordToComplete $WordToComplete
    foreach ($item in $filtered) {
        New-CompletionResult -Value $item
    }
}

$script:MillenniumCompleterCommands = @(
    'millennium',
    'millennium-diag',
    'millennium-mcp',
    'millennium-purge',
    'millennium-repair',
    'millennium-schedule',
    'millennium-theme',
    'millennium-upgrade'
)

foreach ($cmd in $script:MillenniumCompleterCommands) {
    Register-ArgumentCompleter -Native -CommandName $cmd -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $name = $commandAst.GetCommandName()
        if ([string]::IsNullOrEmpty($name) -and $commandAst.CommandElements.Count -gt 0) {
            $name = $commandAst.CommandElements[0].Extent.Text
        }
        Complete-MillenniumNative -CommandName $name -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
    }
}
