# Millennium Helper Scripts

[![Test Suite](https://github.com/bolens/millenium-helpers/actions/workflows/test-suite.yml/badge.svg)](https://github.com/bolens/millenium-helpers/actions/workflows/test-suite.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A cross-platform set of utility scripts for managing, repairing, upgrading, rolling back, viewing logs, managing themes, and scheduling updates (for both the client and skins) for the [Millennium](https://github.com/SteamClientHomebrew/Millennium) Steam Client homebrew hook on Linux and Windows.

---

## Table of Contents

- [Features](#features)
- [Installation & Setup](#installation--setup)
  - [Linux/Unix Prerequisites & Setup](#linuxunix-prerequisites--setup)
  - [Windows Prerequisites & Setup](#windows-prerequisites--setup)
- [Management Commands](#management-commands)
- [Environment Variables](#environment-variables)
- [Unified Configuration File](#unified-configuration-file)
- [Dry-Run Mode & Manual Uninstall](docs/uninstall_dryrun.md)
- [Shell Autocompletions](#shell-autocompletions)
- [Script Overview](#script-overview)
- [Model Context Protocol (MCP) Server](docs/mcp.md)
- [Security & Troubleshooting](docs/security_troubleshooting.md)
- [Steam Deck & Flatpak](docs/steam_deck.md)
- [Development](#development)
- [License](#license)

---

## Features

- **Cross-Platform Support**: Feature-parity between Linux/Unix (Bash shell scripts) and Windows (PowerShell scripts).
- **Unified Dispatcher**: Optional `millennium <command>` entrypoint (e.g. `millennium diag`) alongside the individual binaries.
- **Automated Installation & Setup**: Installs the helper tools system-wide and configures autocompletions, with a short getting-started guide after install.
- **Daily Automated Update Scheduler**: Configures a user-level `systemd` timer (Linux) or **Windows Task Scheduler** task (Windows) to run updates daily in the background.
- **Secure by Design**: Utilizes `/etc/sudoers.d/` drop-in configuration (Linux) or Windows UAC elevation safeguards (`sudo` / `Start-Process RunAs`) to execute updates securely. GitHub PATs are entered hidden; Steam close and theme remove confirm interactively.
- **Support for Multiple Release Channels**: Easily switch between `stable` and `beta` updates.
- **Repair Utility**: Ownership correction, cache purging, and theme refreshing from repository metadata.
- **Diagnostic Tool**: Thorough health checks, actionable next-step suggestions, self-repair (`doctor`), and update status analysis.

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

#### Install via curl (One-Liner)
If you prefer not to clone the repository locally, you can download and run the installer in a single command using `curl`:
```bash
curl -fsSL https://raw.githubusercontent.com/bolens/millenium-helpers/main/install.sh | bash -s -- install
```

#### Run or Install via Nix Flake
If you use Nix with flakes enabled, you can run the helpers directly without installing them system-wide:
```bash
nix run github:bolens/millenium-helpers -- --help
```
To install them into your profile:
```bash
nix profile install github:bolens/millenium-helpers
```

#### Install via Homebrew (macOS / Linux)
This repository includes a Homebrew formula at `Formula/millennium-helpers.rb` (MIT-licensed; version comes from the release tag in the `url`). After a release tag is published and packaging hashes are filled in:

```bash
# From a local checkout
brew install --formula ./Formula/millennium-helpers.rb

# Or tap this repo directly (one-time), then install
brew tap bolens/millenium-helpers https://github.com/bolens/millenium-helpers
brew install millennium-helpers
```

Uninstall with `brew uninstall millennium-helpers` (see [Manual Uninstall](docs/uninstall_dryrun.md#4-macos--linux-homebrew-install)).

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

#### Installation & Setup (Windows)
Clone this repository, open a PowerShell terminal, and run the installer script:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install.ps1
```

#### Install via PowerShell (One-Liner)
If you prefer not to clone the repository locally, you can download and run the installer in a single command using `irm`:
```powershell
irm https://raw.githubusercontent.com/bolens/millenium-helpers/main/scripts/windows/install.ps1 | iex
```

#### Run or Install via Scoop
If you use Scoop, you can install the helper tools directly using the repository manifest:
```powershell
scoop install https://raw.githubusercontent.com/bolens/millenium-helpers/main/packaging/scoop/millennium-helpers.json
```

#### Run or Install via Winget
If you use Winget, you can install the helper tools using the repository manifests:
```powershell
winget install --manifest packaging/winget/
```

This installer will:
1. Copy all helper scripts to `$HOME/.millennium-helpers/bin`.
2. Generate `.cmd` wrappers for all scripts (so you can run commands directly by typing `millennium-diag` or `millennium-upgrade` in any command shell or terminal).
3. Add the bin directory to your User `PATH` environment variable.

After installation, run the interactive configuration wizard to configure background update scheduling and update channels:
```powershell
millennium-schedule setup
```

To uninstall the helper scripts and clean up the environment:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install.ps1 -Uninstall
```

---

## Management Commands

### Check Diagnostics and Health Status
```bash
# Linux
millennium-diag

# Windows
millennium-diag
```

### Share Diagnostic Report Online
Upload a sanitized, privacy-safe diagnostic report to a pastebin (`paste.rs`) and return a short link (automatically redacts system user names, user profiles, and active GitHub tokens):
```bash
# Linux & macOS
millennium-diag --share

# Windows
millennium-diag -Share
```

### Run Doctor (Auto-Repair & Self-Update)
Scan your setup for any broken hooks, missing directories, stopped timers, or out-of-date helper scripts, and automatically repair/self-update them:
```bash
# Linux
millennium-diag doctor [--force]

# Windows
millennium-diag doctor
```
*(Or alias `millennium-diag --fix` or `millennium-diag -f`)*

Use the `--force` option to force-run all repairs, permissions adjustments, and completion file updates even if the system is reported healthy.

### Check Update Scheduler Status
```bash
# Linux
millennium-schedule status

# Windows
millennium-schedule status
```

### Disable the Auto-Updater Timer
```bash
# Linux
millennium-schedule disable

# Windows
millennium-schedule disable
```

### Repair Millennium Installation
```bash
# Linux
sudo millennium-repair

# Windows (Run as Administrator)
millennium-repair
```

### Purge/De-register Millennium Client from Steam
```bash
# Linux (prompts for confirmation; use -y/--yes to skip)
sudo millennium-purge
sudo millennium-purge --yes

# Windows (Run as Administrator)
millennium-purge
millennium-purge -Yes
```

### Uninstall All Helper Scripts (Linux)
Remove the binaries, systemd timers, sudoers rules, and shell completions automatically:
```bash
sudo ./install.sh uninstall
```

---

## Environment Variables

The helper scripts respect the following environment variables if defined:

| Variable | Description |
| --- | --- |
| `GITHUB_TOKEN` | Optional. A GitHub Personal Access Token (PAT) used to authenticate API requests. Highly recommended to define if you perform updates frequently to prevent triggering GitHub rate limits. |
| `XDG_CONFIG_HOME` | Optional. Dynamically resolved to locate your user configuration files. Defaults to `~/.config` on Linux. |
| `LOCALAPPDATA` | Used on Windows to locate the user configuration path (`%LOCALAPPDATA%\millennium-helpers`). |
| `NO_COLOR` | Optional. When set to any value, disables ANSI color output in helper scripts. |
| `FORCE_COLOR` | Optional. When set, forces ANSI color output even when stdout is not a TTY. |
| `MILLENNIUM_DEBUG` | Optional (Windows). When set, enables verbose Steam path resolution debug output. |

---

## Unified Configuration File

Instead of managing environment variables, configurations can be stored in a unified JSON file:
* **Linux**: `${XDG_CONFIG_HOME:-~/.config}/millennium-helpers/config.json`
* **Windows**: `%LOCALAPPDATA%\millennium-helpers\config.json`

The configuration file is automatically generated by the interactive setup wizard (`millennium-schedule setup`) and is formatted as follows:
```json
{
  "update_channel": "stable",
  "github_token": "your_github_token_here",
  "backup_limit": 5,
  "backup_max_age_days": 30
}
```

| Key | Type | Description |
| --- | --- | --- |
| `update_channel` | string | Default upgrade channel: `stable` or `beta`. |
| `github_token` | string | Optional GitHub PAT for API authentication (same role as `GITHUB_TOKEN`). |
| `backup_limit` | number | Maximum number of upgrade backups to retain. |
| `backup_max_age_days` | number | Optional. Maximum age in days for retained backups. |

Manage keys with `millennium-schedule config list|get|set`.

*Note: The configuration file permissions are automatically restricted to read/write by the owner (`600`) for security.*



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
De-registers Millennium from all local Steam users and completely purges its files and directories from the system. Non-interactive sessions require `-y` / `--yes` (Linux/macOS) or `-Yes` (Windows); the MCP `millennium_purge` tool always passes that flag.

### 6. [scripts/millennium-diag.sh](scripts/millennium-diag.sh) / `millennium-diag.ps1`
Runs a comprehensive system health check (reports running status of Steam, the installed version of Millennium, configurations, and permissions) with auto-fix (doctor) and secure pastebin log sharing options.

### 7. [scripts/millennium-theme.sh](scripts/millennium-theme.sh) / `millennium-theme.ps1`
A skin/theme manager CLI. Allows listing themes, installing skin repositories from GitHub, checking for updates, and removing skin directories.

### 8. [scripts/millennium-mcp.py](scripts/millennium-mcp.py) (`millennium-mcp`)
A Model Context Protocol (MCP) server. Exposes the entire suite of Millennium helper scripts as native AI tools to coding assistants (like Claude Desktop, Cursor, Windsurf, or Antigravity), allowing them to dynamically run diagnostics, manage themes, apply repairs, and perform upgrades directly.

For detailed setup, configurations, and the list of exposed tools, see the [MCP Server Guide](docs/mcp.md).

---

## Security & Troubleshooting

For details on security boundaries, privilege delegation, and troubleshooting common issues (such as blank/black screens or inactive background timers), see the [Security & Troubleshooting Guide](docs/security_troubleshooting.md).

For **Steam Deck** and **Flatpak Steam** (hooks, sandbox overrides, Desktop Mode, post-OS-update recovery), see the [Steam Deck & Flatpak Guide](docs/steam_deck.md).

Manual pages ship with the helpers (`man/millennium-*.1`) and are installed by `install.sh`, Homebrew, and packaging recipes (`man millennium-diag`, `man millennium-upgrade`, …).

---

## Packaging for Arch Linux (AUR)

If you use Arch Linux, you can package and install the helper scripts natively via the provided PKGBUILD recipes in the [packaging/](packaging/) directory:

- **`millennium-helpers-git`**: Resolves dependencies, installs all executables to `/usr/bin/`, sets up completions, and deploys the passwordless sudoers update rules for the `%wheel` group.

To build and install the package locally:
```bash
cd packaging
makepkg -si
```

---

## Development

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, testing, and conventions.

Quick start:
```bash
make setup      # install shellcheck + ruff
make check-all  # lint + full test suite
```

Helpers report their version via `--version` / `-V` (reads the repo `VERSION` file). A Dev Container (Arch-based sandbox with PowerShell, Nix, and Docker-in-Docker) and Nix `devShell` are also available for a reproducible environment.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
