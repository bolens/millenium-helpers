# Manual Uninstallation & Dry-Run Operations

This guide provides deep-dive instructions for manually cleaning up / uninstalling Millennium helper scripts across different platforms and using Dry-Run mode to safely audit actions.

For general usage instructions, see the main [README.md](../README.md).

---

## Dry-Run Mode

All scripts support a Dry-Run mode (`--dry-run` or `-d`) to preview file copies, configuration generation, permissions fixes, and scheduler task registrations without modifying the system state:

```bash
# Linux (Natively Installed)
./install.sh --dry-run
millennium-upgrade --channel stable --dry-run
millennium-repair --dry-run

# Windows
millennium-upgrade -Channel stable -DryRun
millennium-diag doctor -DryRun
```

When run in Dry-Run mode, scripts log exactly what files would be created, moved, or deleted, and what commands would be executed, without committing any changes.

---

## Manual Uninstallation / Cleanup

If you prefer to clean up and remove the helper scripts manually instead of using the provided installers, follow the steps below matching your installation type.

### 1. Linux (System-Wide Install)

If you ran `sudo ./install.sh install`, follow these steps to clean up all components:

1. **Disable and remove the daily update systemd user timer**:
   ```bash
   systemctl --user disable --now millennium-update.timer
   systemctl --user stop millennium-update.service
   rm -f ${XDG_CONFIG_HOME:-~/.config}/systemd/user/millennium-update.timer \
         ${XDG_CONFIG_HOME:-~/.config}/systemd/user/millennium-update.service
   systemctl --user daemon-reload
   ```

2. **Remove the script binaries from `/usr/local/bin`**:
   ```bash
   sudo rm -f /usr/local/bin/millennium-repair \
              /usr/local/bin/millennium-upgrade \
              /usr/local/bin/millennium-schedule \
              /usr/local/bin/millennium-purge \
              /usr/local/bin/millennium-diag \
              /usr/local/bin/millennium-theme \
              /usr/local/bin/millennium-mcp
   ```

3. **Remove the passwordless sudoers rules**:
   ```bash
   sudo rm -f /etc/sudoers.d/millennium-helpers
   ```

4. **Remove shell autocompletion configurations**:
   ```bash
   # Bash completions & symlinks
   sudo rm -f /usr/share/bash-completion/completions/millennium-helpers \
              /usr/share/bash-completion/completions/millennium-repair \
              /usr/share/bash-completion/completions/millennium-upgrade \
              /usr/share/bash-completion/completions/millennium-schedule \
              /usr/share/bash-completion/completions/millennium-purge \
              /usr/share/bash-completion/completions/millennium-diag \
              /usr/share/bash-completion/completions/millennium-theme \
              /usr/share/bash-completion/completions/millennium-mcp
   
   # Zsh completions & symlinks
   sudo rm -f /usr/share/zsh/site-functions/_millennium-helpers \
              /usr/share/zsh/site-functions/_millennium-repair \
              /usr/share/zsh/site-functions/_millennium-upgrade \
              /usr/share/zsh/site-functions/_millennium-schedule \
              /usr/share/zsh/site-functions/_millennium-purge \
              /usr/share/zsh/site-functions/_millennium-diag \
              /usr/share/zsh/site-functions/_millennium-theme \
              /usr/share/zsh/site-functions/_millennium-mcp
   
   # Fish completions
   sudo rm -f /usr/share/fish/vendor_completions.d/millennium-repair.fish \
              /usr/share/fish/vendor_completions.d/millennium-upgrade.fish \
              /usr/share/fish/vendor_completions.d/millennium-schedule.fish \
              /usr/share/fish/vendor_completions.d/millennium-purge.fish \
              /usr/share/fish/vendor_completions.d/millennium-diag.fish \
              /usr/share/fish/vendor_completions.d/millennium-theme.fish
   
   # Nushell completions
   sudo rm -f /usr/share/nushell/completions/millennium-helpers.nu \
              /usr/local/share/nushell/completions/millennium-helpers.nu
   ```

5. **Remove configuration files**:
   ```bash
   rm -rf ${XDG_CONFIG_HOME:-~/.config}/millennium-helpers
   ```

### 2. Linux (Arch Linux AUR Install)

If you installed via `millennium-helpers-git` from the AUR, all file locations (binaries in `/usr/bin/`, completions, systemd units, and sudoers rules) are fully tracked by `pacman`. Simply run:

```bash
sudo pacman -R millennium-helpers-git
```

This will cleanly and completely remove all system-wide files. You can optionally clean up user-level configuration files:
```bash
rm -rf ${XDG_CONFIG_HOME:-~/.config}/millennium-helpers
```

### 3. Linux (Nix Profile Install)

If you installed the helpers via `nix profile install github:bolens/millenium-helpers`, Nix isolates files inside the Nix store. 

1. **Remove from Nix profile**:
   ```bash
   nix profile remove github:bolens/millenium-helpers
   ```
   *(Or query `nix profile list` and remove by package number, e.g., `nix profile remove 2`)*

2. **Clean up user-level configs**:
   ```bash
   rm -rf ${XDG_CONFIG_HOME:-~/.config}/millennium-helpers
   ```

### 4. Windows (Standard Install)

If you ran the Windows installer script (`install.ps1`), follow these steps to clean up all components manually:

1. **Remove the daily auto-update scheduled task**:
   ```powershell
   Unregister-ScheduledTask -TaskName "MillenniumUpdate" -Confirm:$false
   ```

2. **Remove the binaries and wrappers directory**:
   ```powershell
   Remove-Item -Path "$HOME\.millennium-helpers" -Recurse -Force -ErrorAction SilentlyContinue
   ```

3. **Remove from PATH environment variable**:
   Retrieve the current user `PATH` variable, filter out the `$HOME\.millennium-helpers\bin` path, and update the environment:
   ```powershell
   $targetPath = Join-Path -Path $HOME -ChildPath ".millennium-helpers\bin"
   $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
   $newPath = ($currentPath -split ';' | Where-Object { $_ -ne $targetPath }) -join ';'
   [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
   ```

4. **Remove configuration files**:
   ```powershell
   Remove-Item -Path "$env:LOCALAPPDATA\millennium-helpers" -Recurse -Force -ErrorAction SilentlyContinue
   ```

### 5. Windows (Scoop Install)

If you installed the helpers via Scoop, uninstallation is fully automated:

1. **Uninstall package**:
   ```powershell
   scoop uninstall millennium-helpers
   ```

2. **Clean up user-level configs (optional)**:
   ```powershell
   Remove-Item -Path "$env:LOCALAPPDATA\millennium-helpers" -Recurse -Force -ErrorAction SilentlyContinue
   ```

### 6. Windows (Winget Install)

If you installed the helpers via Winget, uninstallation is fully automated:

1. **Uninstall package**:
   ```powershell
   winget uninstall bolens.millenniumhelpers
   ```

2. **Clean up user-level configs (optional)**:
   ```powershell
   Remove-Item -Path "$env:LOCALAPPDATA\millennium-helpers" -Recurse -Force -ErrorAction SilentlyContinue
   ```
