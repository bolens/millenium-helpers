# Manual Uninstallation & Dry-Run Operations

This guide provides deep-dive instructions for manually cleaning up / uninstalling Millennium helper scripts across different platforms and using Dry-Run mode to safely audit actions.

For general usage instructions, see the main [README.md](../README.md). Full
docs index: [README.md](README.md). Licensing: [licensing.md](licensing.md).
Steam Deck / Flatpak: [steam_deck.md](steam_deck.md).

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

If you installed via the standard installer script:
* **Option A: Piped Uninstall (One-Liner)**:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/bolens/millenium-helpers/main/install.sh | sudo bash -s -- uninstall
  ```
  *(Add `--purge` at the end to also purge all Millennium hook/client files)*

* **Option B: Manual Cleanup**:
  Follow these steps to clean up all components manually:

1. **Disable and remove the daily update systemd timers** (system and user scopes).
   Preferred:
   ```bash
   sudo millennium schedule disable
   # or: sudo millennium-schedule disable
   ```
   Manual equivalent:
   ```bash
   # System scope (if present)
   sudo systemctl disable --now millennium-update.timer
   sudo systemctl stop millennium-update.service
   sudo rm -f /etc/systemd/system/millennium-update.timer \
              /etc/systemd/system/millennium-update.service
   sudo systemctl daemon-reload

   # User scope
   systemctl --user disable --now millennium-update.timer
   systemctl --user stop millennium-update.service
   rm -f ${XDG_CONFIG_HOME:-~/.config}/systemd/user/millennium-update.timer \
         ${XDG_CONFIG_HOME:-~/.config}/systemd/user/millennium-update.service
   systemctl --user daemon-reload
   ```

2. **Remove the script binaries from `/usr/local/bin`**:
   ```bash
   sudo rm -f /usr/local/bin/millennium \
              /usr/local/bin/millennium-repair \
              /usr/local/bin/millennium-upgrade \
              /usr/local/bin/millennium-schedule \
              /usr/local/bin/millennium-purge \
              /usr/local/bin/millennium-diag \
              /usr/local/bin/millennium-theme \
              /usr/local/bin/millennium-mcp
   ```

3. **Remove the shared helper library**:
   ```bash
   sudo rm -rf /usr/local/lib/millennium-helpers
   ```
   *(AUR packages use `/usr/lib/millennium-helpers` instead — prefer `pacman -R` for those installs.)*

4. **Remove the passwordless sudoers rules**:
   ```bash
   sudo rm -f /etc/sudoers.d/millennium-helpers
   ```

5. **Remove shell autocompletion configurations**:
   ```bash
   # Bash completions & symlinks
   sudo rm -f /usr/share/bash-completion/completions/millennium-helpers \
              /usr/share/bash-completion/completions/millennium \
              /usr/share/bash-completion/completions/millennium-repair \
              /usr/share/bash-completion/completions/millennium-upgrade \
              /usr/share/bash-completion/completions/millennium-schedule \
              /usr/share/bash-completion/completions/millennium-purge \
              /usr/share/bash-completion/completions/millennium-diag \
              /usr/share/bash-completion/completions/millennium-theme \
              /usr/share/bash-completion/completions/millennium-mcp

   # Zsh completions & symlinks
   sudo rm -f /usr/share/zsh/site-functions/_millennium-helpers \
              /usr/share/zsh/site-functions/_millennium \
              /usr/share/zsh/site-functions/_millennium-repair \
              /usr/share/zsh/site-functions/_millennium-upgrade \
              /usr/share/zsh/site-functions/_millennium-schedule \
              /usr/share/zsh/site-functions/_millennium-purge \
              /usr/share/zsh/site-functions/_millennium-diag \
              /usr/share/zsh/site-functions/_millennium-theme \
              /usr/share/zsh/site-functions/_millennium-mcp

   # Fish completions (including the millennium dispatcher)
   sudo rm -f /usr/share/fish/vendor_completions.d/millennium.fish \
              /usr/share/fish/vendor_completions.d/millennium-repair.fish \
              /usr/share/fish/vendor_completions.d/millennium-upgrade.fish \
              /usr/share/fish/vendor_completions.d/millennium-schedule.fish \
              /usr/share/fish/vendor_completions.d/millennium-purge.fish \
              /usr/share/fish/vendor_completions.d/millennium-diag.fish \
              /usr/share/fish/vendor_completions.d/millennium-theme.fish \
              /usr/share/fish/vendor_completions.d/millennium-mcp.fish

   # Nushell completions
   sudo rm -f /usr/share/nushell/completions/millennium-helpers.nu \
              /usr/local/share/nushell/completions/millennium-helpers.nu \
              ${XDG_CONFIG_HOME:-~/.config}/nushell/completions/millennium-helpers.nu

   # Man pages
   sudo rm -f /usr/local/share/man/man1/millennium-*.1 \
              /usr/share/man/man1/millennium-*.1
   ```

6. **Remove configuration and state files**:
   ```bash
   rm -rf ${XDG_CONFIG_HOME:-~/.config}/millennium-helpers
   rm -rf ${XDG_STATE_HOME:-~/.local/state}/millennium-helpers
   ```

### 2. Linux (Arch Linux AUR Install)

If you installed via `millennium-helpers` or `millennium-helpers-git` from the AUR (or a local PKGBUILD), all file locations (binaries in `/usr/bin/`, completions, systemd units, and sudoers rules) are fully tracked by `pacman`. Simply run:

```bash
sudo pacman -R millennium-helpers
# or, if you installed the VCS package:
sudo pacman -R millennium-helpers-git
```

This will cleanly and completely remove all system-wide files. You can optionally clean up user-level configuration and state:
```bash
rm -rf ${XDG_CONFIG_HOME:-~/.config}/millennium-helpers
rm -rf ${XDG_STATE_HOME:-~/.local/state}/millennium-helpers
# User systemd timer units (if you enabled the scheduler)
rm -f ${XDG_CONFIG_HOME:-~/.config}/systemd/user/millennium-update.timer \
      ${XDG_CONFIG_HOME:-~/.config}/systemd/user/millennium-update.service
systemctl --user daemon-reload 2>/dev/null || true
```

### 3. Linux (Nix Profile Install)

If you installed the helpers via `nix profile install github:bolens/millenium-helpers`, Nix isolates files inside the Nix store.

1. **Remove from Nix profile**:
   ```bash
   nix profile remove github:bolens/millenium-helpers
   # or, if you installed the tip-of-flake package:
   nix profile remove github:bolens/millenium-helpers#millennium-helpers-git
   ```
   *(Or query `nix profile list` and remove by package number, e.g., `nix profile remove 2`)*

2. **Clean up user-level configs**:
   ```bash
   rm -rf ${XDG_CONFIG_HOME:-~/.config}/millennium-helpers
   rm -rf ${XDG_STATE_HOME:-~/.local/state}/millennium-helpers
   ```

### 4. macOS / Linux (Homebrew Install)

If you installed the helpers via Homebrew (`Formula/millennium-helpers.rb` in this repo):

1. **Uninstall the formula**:
   ```bash
   brew uninstall millennium-helpers
   ```

   If you tapped this repository earlier, you can also remove the tap:
   ```bash
   brew untap bolens/millenium-helpers
   ```

2. **Clean up user-level configs (optional)**:
   ```bash
   rm -rf ${XDG_CONFIG_HOME:-~/.config}/millennium-helpers
   rm -rf ${XDG_STATE_HOME:-~/.local/state}/millennium-helpers
   ```

   Homebrew does not remove Millennium client hooks under Steam; use `sudo millennium-purge --yes` before uninstalling the formula if you also want those gone.

### 5. Windows (Standard Install)

If helpers are on your `PATH` (Scoop, Winget, Chocolatey, or `millennium install`):
* **Option A: Uninstall helpers**:
  ```powershell
  millennium uninstall
  ```

* **Option B: Manual Cleanup**:
  Follow these steps to clean up all components manually:

1. **Remove the daily auto-update scheduled task**:
   ```powershell
   Unregister-ScheduledTask -TaskName "MillenniumUpdate" -Confirm:$false
   ```

2. **Remove PowerShell completion profile hooks** (Tab completion):
   The installer may have added a line that dot-sources
   `millennium-helpers.completion.ps1` into your PowerShell profile(s).
   Remove those lines from:
   - `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` (pwsh)
   - `$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` (Windows PowerShell 5.1)

   Or run:
   ```powershell
   $profiles = @(
     "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
     "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
   )
   foreach ($p in $profiles) {
     if (!(Test-Path $p)) { continue }
     $content = Get-Content $p -Raw
     if ($content -notlike "*millennium-helpers.completion.ps1*") { continue }
     $filtered = ($content -split "`n" | Where-Object {
       $_ -notmatch 'millennium-helpers\.completion\.ps1' -and
       $_ -notmatch '^\s*# Millennium Helpers completions\s*$'
     }) -join "`n"
     Set-Content -Path $p -Value $filtered -Encoding UTF8
   }
   ```

3. **Remove the binaries, wrappers, and completer directory**:
   ```powershell
   Remove-Item -Path "$HOME\.millennium-helpers" -Recurse -Force -ErrorAction SilentlyContinue
   ```
   *(This also deletes `bin\millennium-helpers.completion.ps1`.)*

4. **Remove from PATH environment variable**:
   Retrieve the current user `PATH` variable, filter out the `$HOME\.millennium-helpers\bin` path, and update the environment:
   ```powershell
   $targetPath = Join-Path -Path $HOME -ChildPath ".millennium-helpers\bin"
   $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
   $newPath = ($currentPath -split ';' | Where-Object { $_ -ne $targetPath }) -join ';'
   [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
   ```

5. **Remove configuration files**:
   ```powershell
   Remove-Item -Path "$env:LOCALAPPDATA\millennium-helpers" -Recurse -Force -ErrorAction SilentlyContinue
   ```

### 6. Windows (Scoop Install)

If you installed the helpers via Scoop, uninstallation is mostly automated:

1. **Uninstall package**:
   ```powershell
   scoop uninstall millennium-helpers
   # or, if you installed the tip-of-main package:
   scoop uninstall millennium-helpers-git
   ```
   This runs `pre_uninstall` hooks that remove PowerShell completion profile
   lines and the `MillenniumUpdate` scheduled task (if present).

2. **Clean up user-level configs (optional)**:
   ```powershell
   Remove-Item -Path "$env:LOCALAPPDATA\millennium-helpers" -Recurse -Force -ErrorAction SilentlyContinue
   ```

### 7. Windows (Winget Install)

**Normal install** (once the package is in the winget community repository):

```powershell
winget install bolens.millenniumhelpers
```

**Uninstall:**

```powershell
winget uninstall bolens.millenniumhelpers
# or tip-of-main:
winget uninstall bolens.millenniumhelpers.git
```

Optional config cleanup:

```powershell
Remove-Item -Path "$env:LOCALAPPDATA\millennium-helpers" -Recurse -Force -ErrorAction SilentlyContinue
```

If a PowerShell profile still references `millennium-helpers.completion.ps1`, remove that hook using the steps in the Windows manual cleanup section above.

**Local manifest testing** (developers / pre-approval only): installs from the YAML in this repo instead of the community source. Use this to exercise `packaging/winget/` or `packaging/winget-git/` from a clone while polishing manifests — not for end-user installs.

```powershell
# from the repo root
winget install --manifest packaging/winget/
winget uninstall bolens.millenniumhelpers

# tip-of-main package (uninstall release package first if both would conflict)
winget install --manifest packaging/winget-git/
winget uninstall bolens.millenniumhelpers.git
```

## Related

- **Docs index:** [README.md](README.md)
- **Project:** [README.md](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [SECURITY.md](../SECURITY.md)
- **Guides:** [security_troubleshooting.md](security_troubleshooting.md) · [steam_deck.md](steam_deck.md) · [licensing.md](licensing.md) · [mcp.md](mcp.md)
