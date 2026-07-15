# PowerShell argument completers for Millennium Helpers.
# Dot-source from your profile, or let `millennium install` register a profile hook:
#   . "$HOME/.millennium-helpers/bin/millennium-helpers.completion.ps1"

Set-StrictMode -Version Latest

function Global:Get-MillenniumDispatcherCommands {
    @('diag', 'doctor', 'upgrade', 'schedule', 'theme', 'repair', 'purge', 'mcp', 'install', 'uninstall', 'help')
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

    if ($CommandName -ne 'millennium') {
        return
    }

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
                $candidates = @('--channel', '-c', '--stable', '--beta', '--main', '--rollback', '-r', '--file', '--sha256', '--insecure-skip-verify', '--all-users', '--force', '-f', '--yes', '-y', '--dry-run', '-d', '--quiet', '-q', '--version', '-V', '--help', '-h')
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
            'install' {
                $candidates = @('--track', '--tag', '--allow-unsigned-main', '--prefix', '--target-dir', '--lib-dir', '--source-root', '--skip-wizard', '--dry-run', '-d', '--force', '-f', '--version', '-V', '--help', '-h')
            }
            'uninstall' {
                $candidates = @('--purge', '-p', '--prefix', '--target-dir', '--lib-dir', '--dry-run', '-d', '--version', '-V', '--help', '-h')
            }
        }
    }

    $filtered = Filter-Completions -Candidates $candidates -WordToComplete $WordToComplete
    foreach ($item in $filtered) {
        New-CompletionResult -Value $item
    }
}

Register-ArgumentCompleter -Native -CommandName 'millennium' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $name = $commandAst.GetCommandName()
    if ([string]::IsNullOrEmpty($name) -and $commandAst.CommandElements.Count -gt 0) {
        $name = $commandAst.CommandElements[0].Extent.Text
    }
    Complete-MillenniumNative -CommandName $name -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
