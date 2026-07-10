# Dispatcher: millennium <command> [args...]
complete -c millennium -f -n 'not __fish_seen_subcommand_from diag doctor upgrade schedule theme repair purge mcp help' -a 'diag' -d 'Run diagnostics'
complete -c millennium -f -n 'not __fish_seen_subcommand_from diag doctor upgrade schedule theme repair purge mcp help' -a 'doctor' -d 'Alias for diag doctor'
complete -c millennium -f -n 'not __fish_seen_subcommand_from diag doctor upgrade schedule theme repair purge mcp help' -a 'upgrade' -d 'Upgrade / install Millennium'
complete -c millennium -f -n 'not __fish_seen_subcommand_from diag doctor upgrade schedule theme repair purge mcp help' -a 'schedule' -d 'Manage auto-update scheduler'
complete -c millennium -f -n 'not __fish_seen_subcommand_from diag doctor upgrade schedule theme repair purge mcp help' -a 'theme' -d 'Manage skins/themes'
complete -c millennium -f -n 'not __fish_seen_subcommand_from diag doctor upgrade schedule theme repair purge mcp help' -a 'repair' -d 'Repair hooks and ownership'
complete -c millennium -f -n 'not __fish_seen_subcommand_from diag doctor upgrade schedule theme repair purge mcp help' -a 'purge' -d 'Uninstall Millennium'
complete -c millennium -f -n 'not __fish_seen_subcommand_from diag doctor upgrade schedule theme repair purge mcp help' -a 'mcp' -d 'Run / register MCP server'
complete -c millennium -f -n 'not __fish_seen_subcommand_from diag doctor upgrade schedule theme repair purge mcp help' -a 'help' -d 'Show help'

# diag
complete -c millennium -f -n '__fish_seen_subcommand_from diag' -a 'doctor' -d 'Repair partial or broken installations'
complete -c millennium -f -n '__fish_seen_subcommand_from diag' -a 'logs' -d 'Show recent Millennium / Steam logs'
complete -c millennium -f -n '__fish_seen_subcommand_from diag' -l json -d 'JSON output'
complete -c millennium -f -n '__fish_seen_subcommand_from diag' -s f -l fix -d 'Alias for doctor'
complete -c millennium -f -n '__fish_seen_subcommand_from diag' -s y -l yes -d 'Skip Steam close confirmation'
complete -c millennium -f -n '__fish_seen_subcommand_from diag' -s d -l dry-run -d 'Simulation mode'
complete -c millennium -f -n '__fish_seen_subcommand_from diag' -s q -l quiet -d 'Suppress informational output'
complete -c millennium -f -n '__fish_seen_subcommand_from diag' -s h -l help -d 'Show help'

# upgrade
complete -c millennium -f -n '__fish_seen_subcommand_from upgrade' -s c -l channel -d 'Update channel' -a 'stable beta'
complete -c millennium -f -n '__fish_seen_subcommand_from upgrade' -l stable -d 'Alias for --channel stable'
complete -c millennium -f -n '__fish_seen_subcommand_from upgrade' -l beta -d 'Alias for --channel beta'
complete -c millennium -f -n '__fish_seen_subcommand_from upgrade' -s r -l rollback -d 'Roll back to a previous backup'
complete -c millennium -f -n '__fish_seen_subcommand_from upgrade' -s f -l force -d 'Force reinstall'
complete -c millennium -f -n '__fish_seen_subcommand_from upgrade' -s y -l yes -d 'Skip Steam close confirmation'
complete -c millennium -f -n '__fish_seen_subcommand_from upgrade' -s d -l dry-run -d 'Simulation mode'
complete -c millennium -f -n '__fish_seen_subcommand_from upgrade' -s q -l quiet -d 'Suppress informational output'

# schedule
complete -c millennium -f -n '__fish_seen_subcommand_from schedule' -a 'enable disable status setup config' -d 'Schedule command'
complete -c millennium -f -n '__fish_seen_subcommand_from schedule' -s c -l cron -d 'Force use of crontab instead of systemd'
complete -c millennium -f -n '__fish_seen_subcommand_from schedule' -s d -l dry-run -d 'Simulation mode'
complete -c millennium -f -n '__fish_seen_subcommand_from schedule' -s q -l quiet -d 'Suppress informational output'

# theme
complete -c millennium -f -n '__fish_seen_subcommand_from theme' -a 'list install update remove' -d 'Theme command'
complete -c millennium -f -n '__fish_seen_subcommand_from theme' -l json -d 'JSON list output'
complete -c millennium -f -n '__fish_seen_subcommand_from theme' -s y -l yes -d 'Skip remove confirmation'
complete -c millennium -f -n '__fish_seen_subcommand_from theme' -s d -l dry-run -d 'Simulation mode'
complete -c millennium -f -n '__fish_seen_subcommand_from theme' -s q -l quiet -d 'Suppress informational output'

# repair / purge / mcp
complete -c millennium -f -n '__fish_seen_subcommand_from repair' -s y -l yes -d 'Skip Steam close confirmation'
complete -c millennium -f -n '__fish_seen_subcommand_from repair' -s d -l dry-run -d 'Simulation mode'
complete -c millennium -f -n '__fish_seen_subcommand_from repair' -s q -l quiet -d 'Suppress informational output'
complete -c millennium -f -n '__fish_seen_subcommand_from purge' -s y -l yes -d 'Skip confirmation'
complete -c millennium -f -n '__fish_seen_subcommand_from purge' -s d -l dry-run -d 'Simulation mode'
complete -c millennium -f -n '__fish_seen_subcommand_from purge' -s q -l quiet -d 'Suppress informational output'
complete -c millennium -f -n '__fish_seen_subcommand_from mcp' -s r -l register -d 'Register with AI clients'
