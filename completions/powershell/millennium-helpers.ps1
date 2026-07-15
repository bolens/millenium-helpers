# PowerShell argument completers for Millennium Helpers.
# Dot-source from your profile, or let `millennium install` register a profile hook:
#   . "$HOME/.millennium-helpers/bin/millennium-helpers.completion.ps1"

Set-StrictMode -Version Latest

function Global:Get-MillenniumDispatcherCommands {
# @@cli-contract:dispatcher.commands@@
    @('diag', 'doctor', 'upgrade', 'schedule', 'theme', 'repair', 'purge', 'mcp', 'install', 'uninstall', 'help')
# @@/cli-contract:dispatcher.commands@@
}

function Global:Get-MillenniumScheduleActions {
# @@cli-contract:commands.schedule.subcommands@@
    @('enable', 'disable', 'status', 'setup', 'config')
# @@/cli-contract:commands.schedule.subcommands@@
}

function Global:Get-MillenniumScheduleChannels {
# @@cli-contract:channels@@
    @('stable', 'beta', 'main')
# @@/cli-contract:channels@@
}

function Global:Get-MillenniumConfigActions {
    @('get', 'set', 'list')
}

function Global:Get-MillenniumDiagActions {
# @@cli-contract:commands.diag.subcommands@@
    @('doctor', 'logs', '--fix')
# @@/cli-contract:commands.diag.subcommands@@
}

function Global:Get-MillenniumThemeActions {
# @@cli-contract:commands.theme.subcommands@@
    @('list', 'install', 'update', 'remove')
# @@/cli-contract:commands.theme.subcommands@@
}

function Global:Get-MillenniumDiagFlags {
# @@cli-contract:commands.diag.flags@@
    @('-f', '--fix', '--force', '--json', '-l', '--follow', '-s', '--share', '-y', '--yes', '-d', '--dry-run', '-q', '--quiet', '-V', '--version', '-h', '--help')
# @@/cli-contract:commands.diag.flags@@
}

function Global:Get-MillenniumUpgradeFlags {
# @@cli-contract:commands.upgrade.flags@@
    @('-c', '--channel', '--stable', '--beta', '--main', '-r', '--rollback', '--file', '--sha256', '--insecure-skip-verify', '--all-users', '-f', '--force', '-y', '--yes', '-d', '--dry-run', '-q', '--quiet', '-V', '--version', '-h', '--help')
# @@/cli-contract:commands.upgrade.flags@@
}

function Global:Get-MillenniumScheduleFlags {
# @@cli-contract:commands.schedule.flags@@
    @('-c', '--cron', '--system', '--user', '-d', '--dry-run', '-q', '--quiet', '-V', '--version', '-h', '--help')
# @@/cli-contract:commands.schedule.flags@@
}

function Global:Get-MillenniumThemeFlags {
# @@cli-contract:commands.theme.flags@@
    @('-a', '--all', '--json', '-y', '--yes', '-d', '--dry-run', '-q', '--quiet', '-V', '--version', '-h', '--help')
# @@/cli-contract:commands.theme.flags@@
}

function Global:Get-MillenniumRepairFlags {
# @@cli-contract:commands.repair.flags@@
    @('-s', '--skip-theme', '-y', '--yes', '-d', '--dry-run', '-q', '--quiet', '-V', '--version', '-h', '--help')
# @@/cli-contract:commands.repair.flags@@
}

function Global:Get-MillenniumPurgeFlags {
# @@cli-contract:commands.purge.flags@@
    @('-d', '--dry-run', '-y', '--yes', '-q', '--quiet', '-V', '--version', '-h', '--help')
# @@/cli-contract:commands.purge.flags@@
}

function Global:Get-MillenniumMcpFlags {
# @@cli-contract:commands.mcp.flags@@
    @('-r', '--register', '-V', '--version', '-h', '--help')
# @@/cli-contract:commands.mcp.flags@@
}

function Global:Get-MillenniumInstallFlags {
# @@cli-contract:commands.install.flags@@
    @('--track', '--tag', '--allow-unsigned-main', '--prefix', '--target-dir', '--lib-dir', '--source-root', '--skip-wizard', '-d', '--dry-run', '-f', '--force', '-V', '--version', '-h', '--help')
# @@/cli-contract:commands.install.flags@@
}

function Global:Get-MillenniumUninstallFlags {
# @@cli-contract:commands.uninstall.flags@@
    @('-p', '--purge', '--prefix', '--target-dir', '--lib-dir', '-d', '--dry-run', '-V', '--version', '-h', '--help')
# @@/cli-contract:commands.uninstall.flags@@
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
                    $candidates = Get-MillenniumDiagFlags
                }
            }
            'upgrade' {
                $candidates = Get-MillenniumUpgradeFlags
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
                    $candidates = Get-MillenniumScheduleFlags
                }
            }
            'theme' {
                if ($args.Count -eq 1) {
                    $candidates = Get-MillenniumThemeActions
                } else {
                    $candidates = Get-MillenniumThemeFlags
                }
            }
            'repair' {
                $candidates = Get-MillenniumRepairFlags
            }
            'purge' {
                $candidates = Get-MillenniumPurgeFlags
            }
            'mcp' {
                $candidates = Get-MillenniumMcpFlags
            }
            'install' {
                $candidates = Get-MillenniumInstallFlags
            }
            'uninstall' {
                $candidates = Get-MillenniumUninstallFlags
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
