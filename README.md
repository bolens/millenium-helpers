# Millennium Helper Scripts

A cross-platform set of utility scripts for managing, repairing, upgrading, rolling back, viewing logs, managing themes, and scheduling updates (for both the client and skins) for the [Millennium](https://github.com/SteamClientHomebrew/Millennium) Steam Client homebrew hook on Linux and Windows.

---

## Table of Contents

- [Features](#features)
- [Installation & Setup](#installation--setup)
  - [Linux/Unix Prerequisites & Setup](#linuxunix-prerequisites--setup)
  - [Windows Prerequisites & Setup](#windows-prerequisites--setup)
- [Management Commands](#management-commands)
  - [Manual Uninstall / Cleanup](#manual-uninstall--cleanup)
- [Environment Variables](#environment-variables)
- [Unified Configuration File](#unified-configuration-file)
- [Dry-Run Mode](#dry-run-mode)
- [Shell Autocompletions](#shell-autocompletions)
- [Script Overview](#script-overview)
- [Troubleshooting & FAQ](#troubleshooting--faq)
- [Security Design](#security-design)
- [License](#license)

---

## Features

- **Cross-Platform Support**: Feature-parity between Linux/Unix (Bash shell scripts) and Windows (PowerShell scripts).
- **Automated Installation & Setup**: Installs the helper tools system-wide and configures autocompletions.
- **Daily Automated Update Scheduler**: Configures a user-level `systemd` timer (Linux) or **Windows Task Scheduler** task (Windows) to run updates daily in the background.
- **Secure by Design**: Utilizes `/etc/sudoers.d/` drop-in configuration (Linux) or Windows UAC elevation safeguards (`sudo` / `Start-Process RunAs`) to execute updates securely.
- **Support for Multiple Release Channels**: Easily switch between `stable` and `beta` updates.
- **Repair Utility**: Ownership correction, cache purging, and theme refreshing from repository metadata.
- **Diagnostic Tool**: Thorough health checks, version verification, self-repair mechanisms, and update status analysis.

---

## Installation & Setup

### Linux/Unix Prerequisites & Setup

#### Prerequisites
These scripts require standard Linux shell utilities:
- `curl`, `tar`, `awk`, `sha256sum`, `unzip` (for downloads and verification)
- `sudo` and `visudo` (for elevation checks)
- `systemd` or `cron` (for background scheduling)

#### Install System-Wide
Clone this repository and run the installer. The installer launches an **Interactive Configuration Wizard** to guide you through update channel selection (stable vs. beta), background updates configuration, and optional GitHub Personal Access Token (PAT) setup:
```bash
sudo ./install.sh
```
If you prefer a non-interactive installation, pass a specific subcommand:
```bash
sudo ./install.sh install
```

#### Enable the Daily Auto-Updater Timer
Always run the scheduling commands as your **normal user** (without `sudo`) so that systemd configures the background timer inside your own user session space:
```bash
millennium-schedule enable [stable|beta]
```

---

### Windows Prerequisites & Setup

#### Prerequisites
These scripts require Windows PowerShell:
- PowerShell 5.1+ (built-in on Windows 10/11) or PowerShell Core 7+.
- Execution Policy must allow script execution:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

#### Setup & Configuration
Clone this repository, open PowerShell as an Administrator, and run the configuration wizard:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\millennium-schedule.ps1 setup
```
This wizard will prompt you for the update channel, configure the daily background task in **Windows Task Scheduler**, and optionally save your GitHub Personal Access Token.

---

## Management Commands

### Check Diagnostics and Health Status
```bash
# Linux
millennium-diag

# Windows (PowerShell)
powershell -File .\scripts\windows\millennium-diag.ps1
```

### Run Doctor (Auto-Repair & Self-Update)
Scan your setup for any broken hooks, missing directories, stopped timers, or out-of-date helper scripts, and automatically repair/self-update them:
```bash
# Linux
millennium-diag doctor [--force]

# Windows (PowerShell)
powershell -File .\scripts\windows\millennium-diag.ps1 doctor
```
*(Or alias `millennium-diag --fix` or `millennium-diag -f`)*

Use the `--force` option to force-run all repairs, permissions adjustments, and completion file updates even if the system is reported healthy.

### Check Update Scheduler Status
```bash
# Linux
millennium-schedule status

# Windows (PowerShell)
powershell -File .\scripts\windows\millennium-schedule.ps1 status
```

### Disable the Auto-Updater Timer
```bash
# Linux
millennium-schedule disable

# Windows (PowerShell)
powershell -File .\scripts\windows\millennium-schedule.ps1 disable
```

### Repair Millennium Installation
```bash
# Linux
sudo millennium-repair

# Windows (PowerShell - Run as Administrator)
powershell -File .\scripts\windows\millennium-repair.ps1
```

### Purge/De-register Millennium Client from Steam
```bash
# Linux
sudo millennium-purge

# Windows (PowerShell - Run as Administrator)
powershell -File .\scripts\windows\millennium-purge.ps1
```

### Uninstall All Helper Scripts (Linux)
Remove the binaries, systemd timers, sudoers rules, and shell completions automatically:
```bash
sudo ./install.sh uninstall
```

### Manual Uninstall / Cleanup (Linux)
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

---

## Environment Variables

The helper scripts respect the following environment variables if defined:

| Variable | Description |
| --- | --- |
| `GITHUB_TOKEN` | Optional. A GitHub Personal Access Token (PAT) used to authenticate API requests. Highly recommended to define if you perform updates frequently to prevent triggering GitHub rate limits. |
| `XDG_CONFIG_HOME` | Optional. Dynamically resolved to locate your user configuration files. Defaults to `~/.config` on Linux. |
| `LOCALAPPDATA` | Used on Windows to locate the user configuration path (`%LOCALAPPDATA%\millennium-helpers`). |

---

## Unified Configuration File

Instead of managing environment variables, configurations can be stored in a unified JSON file:
* **Linux**: `${XDG_CONFIG_HOME:-~/.config}/millennium-helpers/config.json`
* **Windows**: `%LOCALAPPDATA%\millennium-helpers\config.json`

The configuration file is automatically generated by the interactive setup wizard and is formatted as follows:
```json
{
  "update_channel": "stable",
  "github_token": "your_github_token_here",
  "backup_limit": 5
}
```

*Note: The configuration file permissions are automatically restricted to read/write by the owner (`600`) for security.*

---

## Dry-Run Mode

All scripts support a Dry-Run mode (`--dry-run` or `-d`) to preview file copies, configuration generation, permissions fixes, and scheduler task registrations without modifying the system state:

```bash
# Linux
./install.sh --dry-run
millennium-upgrade --channel stable --dry-run
millennium-repair --dry-run

# Windows (PowerShell)
powershell -File .\scripts\windows\millennium-upgrade.ps1 -Channel stable -DryRun
powershell -File .\scripts\windows\millennium-diag.ps1 doctor -DryRun
```

---

## Shell Autocompletions (Linux)

The installer automatically deploys shell autocompletion configurations for:
- **Bash**: Copied to `/usr/share/bash-completion/completions/` (supports auto-loading for all scripts).
- **Zsh**: Copied to `/usr/share/zsh/site-functions/` (auto-loaded; requires `compinit` in `~/.zshrc`).
- **Fish**: Copied to `/usr/share/fish/vendor_completions.d/`.
- **Nushell**: Copied to `/usr/share/nushell/completions/` or `/usr/local/share/nushell/completions/`.

---

## Script Overview

### 1. [install.sh](install.sh)
The master installer. It copies all helper scripts to `/usr/local/bin`, sets permissions to `755` (read-only for normal users, owned by root), and automatically configures `/etc/sudoers.d/millennium-helpers` for passwordless execution of the updaters.

### 2. [scripts/millennium-repair.sh](scripts/millennium-repair.sh) / `millennium-repair.ps1`
Fixes issues with the Steam theme or settings panel. Corrects directory permissions, flushes CEF cache, and refreshes the active theme using the latest git commit.

### 3. [scripts/millennium-upgrade.sh](scripts/millennium-upgrade.sh) / `millennium-upgrade.ps1`
Downloads, checksum-validates, and installs the latest stable or beta version of Millennium system-wide.
- **Smart Bypass**: Reads the current version info to bypass reinstallation if already up-to-date.
- **Force Reinstall**: Run with `-f` or `--force` to reinstall regardless of version.
- **Rollback Support**: Instantly rolls back to the previously installed client versions.

### 4. [scripts/millennium-schedule.sh](scripts/millennium-schedule.sh) / `millennium-schedule.ps1`
Manages daily update timers and triggers (`systemd` user timers on Linux, **Windows Task Scheduler** tasks on Windows).

### 5. [scripts/millennium-purge.sh](scripts/millennium-purge.sh) / `millennium-purge.ps1`
De-registers Millennium from all local Steam users and completely purges its files and directories from the system.

### 6. [scripts/millennium-diag.sh](scripts/millennium-diag.sh) / `millennium-diag.ps1`
Runs a comprehensive system health check (reports running status of Steam, the installed version of Millennium, configurations, and permissions).

### 7. [scripts/millennium-theme.sh](scripts/millennium-theme.sh) / `millennium-theme.ps1`
A skin/theme manager CLI. Allows listing themes, installing skin repositories from GitHub, checking for updates, and removing skin directories.

### 8. [scripts/millennium-mcp.py](scripts/millennium-mcp.py) (`millennium-mcp`)
A Model Context Protocol (MCP) server. Exposes the entire suite of Millennium helper scripts as native AI tools to coding assistants (like Claude Desktop, Cursor, Windsurf, or Antigravity), allowing them to dynamically run diagnostics, manage themes, apply repairs, and perform upgrades directly.

#### Exposed MCP Tools

| Tool Name | Description | Parameters |
| --- | --- | --- |
| `millennium_diag` | Runs read-only diagnostics or applies auto-repairs in doctor mode. | `doctor` (boolean, optional): set `true` to auto-repair. |
| `millennium_theme` | Manages theme/skin directories (list, install, remove, update). | `action` (string, required): `list`, `install`, `remove`, `update`. <br> `theme` (string, optional): repo or name. <br> `all` (boolean, optional): update all themes. |
| `millennium_upgrade` | Upgrades the Millennium client system-wide. | `channel` (string, optional): `stable` (default) or `beta`. |
| `millennium_schedule` | Manages background auto-update timers. | `action` (string, required): `enable`, `disable`, `status`. <br> `channel` (string, optional): `stable` or `beta`. <br> `cron` (boolean, optional): force crontab (Linux only). |
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

**Claude Desktop**:
* **Linux**: `~/.config/Claude/claude_desktop_config.json`
* **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

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
# Linux
sudo millennium-repair

# Windows
powershell -File .\scripts\windows\millennium-repair.ps1
```

### The background timer is not running updates
1. Check the timer status:
   ```bash
   millennium-schedule status
   ```
2. Verify that passwordless sudo (Linux) or Scheduled Tasks (Windows) are configured correctly.
3. If you want the updates to run even when you are logged out of your session on Linux, enable user lingering:
   ```bash
   loginctl enable-linger $USER
   ```

---

## Security Design

To allow background user-level timers to run updates that modify system directories, the updater scripts must run with elevated privileges. 

This setup achieves this securely:
1. **Sudoers Autoconfiguration (Linux)**: During `sudo ./install.sh`, the installer detects the original invoking user (`SUDO_USER`) and automatically configures a secure drop-in file at `/etc/sudoers.d/millennium-helpers`.
2. **Write-Protected Scripts**: Helper scripts are copied into `/usr/local/bin/` owned by `root:root` with `755` permissions, meaning normal users cannot edit or tamper with them.
3. **Task Scheduler (Windows)**: Scheduled tasks are registered with elevated credentials using native Windows Task Scheduler security boundaries.

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
