# Millennium Helper Scripts

A set of utility scripts for managing, repairing, upgrading, and scheduling updates for the [Millennium](https://github.com/SteamClientHomebrew/Millennium) Steam Client homebrew hook on Linux.

## Installation & Setup

### Prerequisites

These scripts require standard Linux shell utilities to be available on your system path:
- `curl`, `tar`, `awk`, `sha256sum`, `unzip` (for downloads, extraction, and verification)
- `sudo` and `visudo` (for passwordless elevation checks)
- `systemd` (for daily background auto-update scheduling)

### Step 1: Install System-Wide
Clone this repository and run the installer:
```bash
sudo ./install.sh
```

### Step 2: Enable the Daily Auto-Updater Timer
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

## Features

- **Automated Installation & Uninstallation**: Installs the helper tools system-wide into `/usr/local/bin`.
- **Daily Automated Update Scheduler**: Configures a user-level systemd timer and service to run updates daily in the background.
- **Secure by Design**: Utilizes `/etc/sudoers.d/` drop-in configuration to grant limited passwordless privilege escalation specifically for the updater binaries without introducing privilege escalation vectors.
- **Support for Multiple Release Channels**: Easily switch between `stable` and `beta` updates.
- **Repair Utility**: Ownership correction, cache purging, and theme refreshing.

---

## Management Commands

### Check Diagnostics and Health Status
```bash
millennium-diag
```

### Run Doctor (Auto-Repair Broken Installs)
Scan your setup for any broken hooks, missing directories, or stopped timers, and fix them automatically:
```bash
millennium-diag doctor
```
*(Or alias `millennium-diag --fix` or `millennium-diag -f`)*

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
Remove the binaries and the `/etc/sudoers.d/` drop-in file:
```bash
sudo ./install.sh uninstall
```

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

## Script Overview

### 1. [install.sh](install.sh)
The master installer. It copies all helper scripts to `/usr/local/bin`, sets permissions to `755` (read-only for normal users, owned by root), and automatically configures `/etc/sudoers.d/millennium-helpers` for passwordless execution of the updaters.

### 2. [scripts/millennium-repair.sh](scripts/millennium-repair.sh) (`millennium-repair`)
Fixes issues with the Steam theme or settings panel.
- **Offline Resilient**: Automatically detects if the network is down and skips the SpaceTheme download, allowing you to fix local file permissions, caches, and bootstrap links offline.
- **Skip Theme Option**: Pass `-s` or `--skip-theme` to skip downloading the SpaceTheme explicitly.
- Fixes directory permissions and ownership for Millennium config folders.
- Purges the Steam `htmlcache`.
- Re-links bootstrap files (`libXtst.so.6`) for Steam client library hooking.

### 3. [scripts/millennium-upgrade-stable.sh](scripts/millennium-upgrade-stable.sh) (`millennium-upgrade-stable`)
Downloads, checksum-validates, and installs the latest stable version of Millennium system-wide.
- **Smart Bypass**: Reads `/usr/lib/millennium/version.txt` to bypass reinstallation if already up-to-date (saving bandwidth and disk writes).
- **Force Reinstall**: Run with `-f` or `--force` to reinstall regardless of version.

### 4. [scripts/millennium-upgrade-beta.sh](scripts/millennium-upgrade-beta.sh) (`millennium-upgrade-beta`)
Downloads, checksum-validates, and installs the latest prerelease/beta version of Millennium system-wide.
- **Smart Bypass**: Reads `/usr/lib/millennium/version.txt` to bypass reinstallation if already up-to-date.
- **Force Reinstall**: Run with `-f` or `--force` to reinstall regardless of version.

### 5. [scripts/millennium-schedule.sh](scripts/millennium-schedule.sh) (`millennium-schedule`)
Manages systemd user-space timers to run daily updates.

### 6. [scripts/millennium-purge.sh](scripts/millennium-purge.sh) (`millennium-purge`)
De-registers Millennium from all local Steam users and completely purges its files and directories from the system. (Requires `sudo`).

### 7. [scripts/millennium-diag.sh](scripts/millennium-diag.sh) (`millennium-diag`)
Runs a comprehensive system-wide health check on your Millennium setup. It reports the running status of Steam, the installed version of Millennium, the integrity of local user client overrides (including Flatpak sandboxes), auto-update timers, and systemd lingering configurations.

---

## Security Design

To allow background user-level systemd timers to run updates that modify system directories (like `/usr/lib/millennium/`), the updater scripts must run with root privileges. 

This setup achieves this securely using **Option A**:
1. Scripts are copied into `/usr/local/bin/` owned by `root:root` and set as write-protected.
2. A drop-in rule is created at `/etc/sudoers.d/millennium-helpers`.
3. Sudo allows passwordless execution of only `/usr/local/bin/millennium-upgrade-stable` and `/usr/local/bin/millennium-upgrade-beta`.
4. Because the files in `/usr/local/bin/` cannot be modified by your unprivileged user account, this configuration is completely secure and cannot be exploited for local privilege escalation.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
