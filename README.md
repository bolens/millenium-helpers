# Millennium Helper Scripts

A set of utility scripts for managing, repairing, upgrading, rolling back, viewing logs, managing themes, and scheduling updates (for both the client and skins) for the [Millennium](https://github.com/SteamClientHomebrew/Millennium) Steam Client homebrew hook on Linux.

---

## Table of Contents

- [Features](#features)
- [Installation & Setup](#installation--setup)
  - [Prerequisites](#prerequisites)
  - [Step 1: Install System-Wide](#step-1-install-system-wide)
  - [Step 2: Enable the Daily Auto-Updater Timer](#step-2-enable-the-daily-auto-updater-timer)
- [Features](#features)
- [Management Commands](#management-commands)
  - [Uninstall All Helper Scripts](#uninstall-all-helper-scripts)
- [Environment Variables](#environment-variables)
- [Dry-Run Mode](#dry-run-mode)
- [Shell Autocompletions](#shell-autocompletions)
  - [Activating Nushell Completions](#activating-nushell-completions)
- [Script Overview](#script-overview)
- [Troubleshooting & FAQ](#troubleshooting--faq)
- [Security Design](#security-design)
- [License](#license)

---

## Features

- **Automated Installation & Uninstallation**: Installs the helper tools system-wide into `/usr/local/bin` and configures autocompletions.
- **Daily Automated Update Scheduler**: Configures a user-level systemd timer and service to run updates daily in the background.
- **Secure by Design**: Utilizes `/etc/sudoers.d/` drop-in configuration to grant limited passwordless privilege escalation specifically for the updater binaries without introducing privilege escalation vectors.
- **Support for Multiple Release Channels**: Easily switch between `stable` and `beta` updates.
- **Repair Utility**: Cross-distro and Flatpak-resilient ownership correction, cache purging, and theme refreshing from repository metadata.
- **Diagnostic Tool**: Thorough health checks, version verification, self-repair mechanisms, and update status analysis.

---

## Installation & Setup

### Prerequisites

These scripts require standard Linux shell utilities to be available on your system path:
- `curl`, `tar`, `awk`, `sha256sum`, `unzip` (for downloads, extraction, and verification)
- `sudo` and `visudo` (for passwordless elevation checks)
- `systemd` (for daily background auto-update scheduling)

### Step 1: Install System-Wide & Configure
Clone this repository and run the installer. If run in an interactive terminal, the installer will launch an **Interactive Configuration Wizard** to guide you through update channel selection (stable vs. beta), background updates configuration, and optional GitHub Personal Access Token (PAT) setup:
```bash
sudo ./install.sh
```
If you prefer a non-interactive installation, pass a specific subcommand (e.g. `sudo ./install.sh install`).

### Step 2: Enable the Daily Auto-Updater Timer

> [!NOTE]
> Always run the scheduling commands as your **normal user** (without `sudo`) so that systemd configures the background timer inside your own user session space.

Choose which channel you would like to run:

**Stable Channel (Default)**:
```bash
millennium-schedule enable
```

**Beta Channel**:
```bash
millennium-schedule enable beta
```

---

## Management Commands

### Check Diagnostics and Health Status
```bash
millennium-diag
```

### Run Doctor (Auto-Repair & Self-Update)
Scan your setup for any broken hooks, missing directories, stopped timers, or out-of-date helper scripts, and automatically repair/self-update them:
```bash
millennium-diag doctor [--force]
```
*(Or alias `millennium-diag --fix` or `millennium-diag -f`)*

Use the `--force` option to force-run all repairs, permissions adjustments, and completion file updates even if the system is reported healthy.

### Check Update Scheduler Status
```bash
millennium-schedule status
```

### Disable the Auto-Updater Timer
```bash
millennium-schedule disable
```

### Repair Millennium Installation
```bash
sudo millennium-repair
```

### Purge/De-register Millennium Client from Steam
```bash
sudo millennium-purge
```

### Uninstall All Helper Scripts

**Option A: Automated Uninstall (Recommended)**
Remove the binaries, systemd timers, sudoers rules, and shell completions automatically:
```bash
sudo ./install.sh uninstall
```

**Option B: Manual Uninstall**
If you prefer to remove all files and configurations manually, execute the following commands:

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
              /usr/local/bin/millennium-upgrade-beta \
              /usr/local/bin/millennium-upgrade-stable \
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
              /usr/share/bash-completion/completions/millennium-upgrade-beta \
              /usr/share/bash-completion/completions/millennium-upgrade-stable \
              /usr/share/bash-completion/completions/millennium-schedule \
              /usr/share/bash-completion/completions/millennium-purge \
              /usr/share/bash-completion/completions/millennium-diag \
              /usr/share/bash-completion/completions/millennium-theme \
              /usr/share/bash-completion/completions/millennium-mcp

   # Zsh completions & symlinks
   sudo rm -f /usr/share/zsh/site-functions/_millennium-helpers \
              /usr/share/zsh/site-functions/_millennium-repair \
              /usr/share/zsh/site-functions/_millennium-upgrade-beta \
              /usr/share/zsh/site-functions/_millennium-upgrade-stable \
              /usr/share/zsh/site-functions/_millennium-schedule \
              /usr/share/zsh/site-functions/_millennium-purge \
              /usr/share/zsh/site-functions/_millennium-diag \
              /usr/share/zsh/site-functions/_millennium-theme \
              /usr/share/zsh/site-functions/_millennium-mcp

   # Fish completions
   sudo rm -f /usr/share/fish/vendor_completions.d/millennium-repair.fish \
              /usr/share/fish/vendor_completions.d/millennium-upgrade-beta.fish \
              /usr/share/fish/vendor_completions.d/millennium-upgrade-stable.fish \
              /usr/share/fish/vendor_completions.d/millennium-schedule.fish \
              /usr/share/fish/vendor_completions.d/millennium-purge.fish \
              /usr/share/fish/vendor_completions.d/millennium-diag.fish \
              /usr/share/fish/vendor_completions.d/millennium-theme.fish

   # Nushell completions
   sudo rm -f /usr/share/nushell/completions/millennium-helpers.nu \
              /usr/local/share/nushell/completions/millennium-helpers.nu
   ```

---

## Environment Variables

The helper scripts respect the following environment variables if defined:

| Variable | Description |
| --- | --- |
| `GITHUB_TOKEN` | Optional. A GitHub Personal Access Token (PAT) used to authenticate API requests. Highly recommended to define if you perform updates frequently to prevent triggering GitHub rate limits. |
| `XDG_CONFIG_HOME` | Optional. Dynamically resolved to locate your user configuration files. Defaults to `~/.config`. |
| `XDG_DATA_HOME` | Optional. Dynamically resolved to locate your local user data files. Defaults to `~/.local/share`. |

---

## Unified Configuration File

Instead of managing environment variables, configurations can be stored in a unified JSON file located at `${XDG_CONFIG_HOME:-~/.config}/millennium-helpers/config.json`. The configuration file is automatically generated by the interactive installer wizard and is formatted as follows:

```json
{
  "update_channel": "stable",
  "github_token": "your_github_token_here"
}
```

*Note: The configuration file permissions are automatically restricted to read/write by the owner (`600`) for security.*

---

## Dry-Run Mode

All scripts support a Dry-Run mode (`--dry-run` or `-d`) to preview file copies, configuration generation, permissions fixes, and timer commands without actually writing any changes or modifying the system state:

```bash
# Preview the installation
./install.sh --dry-run

# Preview a stable version upgrade
sudo millennium-upgrade-stable --dry-run

# Preview repair operations
sudo millennium-repair --dry-run

# Preview doctor/auto-repair changes
millennium-diag doctor --dry-run
```

---

## Shell Autocompletions

The installer automatically deploys shell autocompletion configurations for:

- **Bash**: Copied to `/usr/share/bash-completion/completions/` (supports auto-loading for all scripts).
- **Zsh**: Copied to `/usr/share/zsh/site-functions/` (auto-loaded; requires `compinit` in `~/.zshrc`).
- **Fish**: Copied to `/usr/share/fish/vendor_completions.d/`.
- **Nushell**: Copied to `/usr/share/nushell/completions/` or `/usr/local/share/nushell/completions/`.

### Activating Nushell Completions
To load completions in Nushell, add the following line to your `~/.config/nushell/config.nu`:
```nushell
use /usr/share/nushell/completions/millennium-helpers.nu *
```
*(Use `/usr/local/share/nushell/completions/millennium-helpers.nu *` if installed under `/usr/local`.)*

---

## Script Overview

### 1. [install.sh](install.sh)
The master installer. It copies all helper scripts to `/usr/local/bin`, sets permissions to `755` (read-only for normal users, owned by root), and automatically configures `/etc/sudoers.d/millennium-helpers` for passwordless execution of the updaters.

### 2. [scripts/millennium-repair.sh](scripts/millennium-repair.sh) (`millennium-repair`)
Fixes issues with the Steam theme or settings panel.
- **XDG & Flatpak Compliant**: Dynamically resolves custom `$XDG_CONFIG_HOME` and `$XDG_DATA_HOME` variables, and loops over Flatpak candidates.
- **Dynamic Active Theme Fetch**: Reads the active theme from the user's config and, if it contains repository metadata, downloads and performs an atomic directory swap with the latest commit from its GitHub source.
- **Offline Resilient**: Skips network downloads automatically when offline to allow correcting permissions and hook links locally.
- **Skip Theme Option**: Pass `-s` or `--skip-theme` to bypass theme downloading explicitly.
- Fixes directory permissions and ownership for Millennium config folders.
- Purges the Steam `htmlcache`.
- Re-links bootstrap files (`libXtst.so.6`) for Steam client library hooking.

### 3. [scripts/millennium-upgrade-stable.sh](scripts/millennium-upgrade-stable.sh) (`millennium-upgrade-stable`)
Downloads, checksum-validates, and installs the latest stable version of Millennium system-wide.
- **Smart Bypass**: Reads `/usr/lib/millennium/version.txt` to bypass reinstallation if already up-to-date (saving bandwidth and disk writes).
- **Force Reinstall**: Run with `-f` or `--force` to reinstall regardless of version.
- **Rollback Support**: Run with `-r` or `--rollback` to restore the previously installed version instantly.

### 4. [scripts/millennium-upgrade-beta.sh](scripts/millennium-upgrade-beta.sh) (`millennium-upgrade-beta`)
Downloads, checksum-validates, and installs the latest prerelease/beta version of Millennium system-wide.
- **Smart Bypass**: Reads `/usr/lib/millennium/version.txt` to bypass reinstallation if already up-to-date.
- **Force Reinstall**: Run with `-f` or `--force` to reinstall regardless of version.
- **Rollback Support**: Run with `-r` or `--rollback` to restore the previously installed version instantly.

### 5. [scripts/millennium-schedule.sh](scripts/millennium-schedule.sh) (`millennium-schedule`)
Manages systemd user-space timers to run daily updates.

### 6. [scripts/millennium-purge.sh](scripts/millennium-purge.sh) (`millennium-purge`)
De-registers Millennium from all local Steam users and completely purges its files and directories from the system. (Requires `sudo`).

### 7. [scripts/millennium-diag.sh](scripts/millennium-diag.sh) (`millennium-diag`)
Runs a comprehensive system-wide health check on your Millennium setup. It reports the running status of Steam, the installed version of Millennium, the integrity of local user client overrides (including Flatpak sandboxes), auto-update timers, and systemd lingering configurations (with optional `--json` structured formatting).

### 8. [scripts/millennium-theme.sh](scripts/millennium-theme.sh) (`millennium-theme`)
A fully-featured skin/theme manager CLI. It allows listing installed themes (with optional `--json` structured formatting), installing new ones directly from GitHub repositories (branch-agnostic), checking/installing theme updates, and removing skin directories.

### 9. [scripts/millennium-mcp.py](scripts/millennium-mcp.py) (`millennium-mcp`)
A zero-dependency Model Context Protocol (MCP) server. Exposes the entire suite of Millennium helper scripts as native AI tools to coding assistants (like Claude Desktop, Cursor, Windsurf, or Antigravity), allowing them to dynamically run diagnostics, manage themes, apply repairs, and perform upgrades directly.

#### Exposed MCP Tools

| Tool Name | Description | Parameters |
| --- | --- | --- |
| `millennium_diag` | Runs read-only diagnostics or applies auto-repairs in doctor mode. | `doctor` (boolean, optional): set `true` to auto-repair. |
| `millennium_theme` | Manages theme/skin directories (list, install, remove, update). | `action` (string, required): `list`, `install`, `remove`, `update`. <br> `theme` (string, optional): repo or name. <br> `all` (boolean, optional): update all themes. |
| `millennium_upgrade` | Upgrades the Millennium client system-wide. | `channel` (string, optional): `stable` (default) or `beta`. |
| `millennium_schedule` | Manages background auto-update timers. | `action` (string, required): `enable`, `disable`, `status`. <br> `channel` (string, optional): `stable` or `beta`. <br> `cron` (boolean, optional): force crontab. |
| `millennium_repair` | Runs system-wide permissions and symlink repairs. | None. |
| `millennium_purge` | Completely uninstalls all Millennium client hooks and files. | None. |

#### Automatic Registration

To automatically register the `millennium-mcp` server with installed AI tools (Claude Desktop and Windsurf), run:
```bash
millennium-mcp --register
```
This detects the config folders for Claude Desktop and Windsurf, updates or creates the JSON configuration files, and adds the `millennium-helpers` server automatically.

#### Configuration Example

To manually enable these tools in your AI assistant, add `millennium-mcp` to your configuration file:

**Claude Desktop** (`~/.config/Claude/claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "millennium-helpers": {
      "command": "millennium-mcp"
    }
  }
}
```

**Cursor / Windsurf**:
Go to Settings -> Features -> MCP, click **+ Add New MCP Server**, and configure:
- **Name**: `millennium-helpers`
- **Type**: `command`
- **Command**: `millennium-mcp`

---

## Troubleshooting & FAQ

### Steam shows a blank/black screen after upgrading Millennium
This is usually caused by outdated CEF cached files. Run the repair utility to fix local permissions and clear Steam's htmlcache:
```bash
sudo millennium-repair
```

### The background timer is not running updates
1. Check the timer status:
   ```bash
   millennium-schedule status
   ```
2. Verify that passwordless sudo is configured correctly. Run `sudo -n -l` as your normal user and verify that `/usr/local/bin/millennium-upgrade-stable`, beta, and `/usr/local/bin/millennium-repair` are listed under `NOPASSWD`.
3. If you want the updates to run even when you are logged out of your session, make sure to enable user lingering:
   ```bash
   loginctl enable-linger $USER
   ```

### Custom Steam Install Paths (Flatpak / Custom Mounts)
The scripts automatically scan multiple paths:
- `~/.local/share/Steam` (Standard native Steam)
- `~/.steam/steam`
- `~/.steam/root`
- `~/.var/app/com.valvesoftware.Steam/.local/share/Steam` (Flatpak Steam)
If you have a custom Steam library installation path, ensure it has a symbolic link pointing to one of these standard locations.

---

## Security Design

To allow background user-level systemd timers to run updates that modify system directories (like `/usr/lib/millennium/`), the updater scripts must run with root privileges. 

This setup achieves this securely:
1. **Sudoers Autoconfiguration**: During `sudo ./install.sh`, the installer detects the original invoking user (`SUDO_USER`) and automatically configures a secure drop-in file at `/etc/sudoers.d/millennium-helpers`.
2. **Write-Protected Scripts**: Helper scripts are copied into `/usr/local/bin/` owned by `root:root` with `755` permissions, meaning normal users cannot edit or tamper with them.
3. **Restricted Sudo Scope**: Sudo permissions are restricted to allow passwordless execution of *only* `/usr/local/bin/millennium-upgrade-stable`, `/usr/local/bin/millennium-upgrade-beta`, `/usr/local/bin/millennium-repair`, and `/usr/local/bin/millennium-diag` (doctor mode) / `/usr/local/bin/millennium-purge`. Because normal users cannot modify these files, this configuration is completely secure and cannot be exploited for local privilege escalation.

---

## Packaging for Arch Linux (AUR)

If you use Arch Linux, you can package and install the helper scripts natively via the provided PKGBUILD recipes in the [packaging/](file:///home/panda/dev/millenium-helpers/packaging/) directory:

- **`millennium-helpers-git`**: Resolves dependencies, installs all executables to `/usr/bin/`, sets up completions, and deploys the passwordless sudoers update rules for the `%wheel` group.

To build and install the package locally:
```bash
cd packaging
makepkg -si
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
