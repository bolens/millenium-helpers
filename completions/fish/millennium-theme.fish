complete -c millennium-theme -f -a 'list' -d 'List installed themes'
complete -c millennium-theme -f -a 'install' -d 'Install a theme from GitHub'
complete -c millennium-theme -f -a 'remove' -d 'Remove an installed theme'
complete -c millennium-theme -f -a 'update' -d 'Update an installed theme'

function __millennium_theme_names
    set -l skins
    for skins in \
        "$HOME/.local/share/Steam/steamui/skins" \
        "$HOME/.steam/steam/steamui/skins" \
        "$HOME/.steam/root/steamui/skins" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamui/skins" \
        "$HOME/Library/Application Support/Steam/steamui/skins"
        if test -d "$skins"
            for d in "$skins"/*/
                basename (string trim -r -c / -- $d)
            end
            return
        end
    end
end

complete -c millennium-theme -f -n '__fish_seen_subcommand_from update' -s a -l all -d 'Update all themes'
complete -c millennium-theme -f -n '__fish_seen_subcommand_from update remove' -a '(__millennium_theme_names)' -d 'Installed theme'
complete -c millennium-theme -l json -d 'Output list results as JSON'
complete -c millennium-theme -s y -l yes -d 'Skip confirmation when removing'
complete -c millennium-theme -s d -l dry-run -d 'Simulation mode'
complete -c millennium-theme -s q -l quiet -d 'Suppress informational output'
complete -c millennium-theme -s h -l help -d 'Show help message'
complete -c millennium-theme -s V -l version -d 'Show version information'
