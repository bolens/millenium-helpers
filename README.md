# Millennium Helper Scripts

[![Test Suite](https://github.com/bolens/millenium-helpers/actions/workflows/test-suite.yml/badge.svg)](https://github.com/bolens/millenium-helpers/actions/workflows/test-suite.yml)
[![Release](https://img.shields.io/github/v/release/bolens/millenium-helpers)](https://github.com/bolens/millenium-helpers/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Windows-blue)](#installation)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

CLI helpers for [Millennium](https://github.com/SteamClientHomebrew/Millennium) — install, repair, upgrade, roll back, diagnose, theme, and schedule updates for the Steam Client homebrew hook on Linux and Windows.

[Getting started](#getting-started) ·
[Installation](#installation) ·
[Commands](#commands) ·
[Configuration](#configuration) ·
[Docs](#further-reading)

---

## Getting started

```bash
# Install (Linux)
curl -fsSL https://raw.githubusercontent.com/bolens/millenium-helpers/main/install.sh | bash -s -- install

# Install (Windows PowerShell)
irm https://raw.githubusercontent.com/bolens/millenium-helpers/main/scripts/windows/install.ps1 | iex
```

Then use the unified dispatcher (or the individual `millennium-*` binaries):

```bash
millennium diag                 # health check
millennium doctor               # auto-repair
millennium upgrade              # install / update Millennium
millennium schedule enable      # daily background updates (Linux)
millennium theme list           # manage skins
millennium --help
```

```text
$ millennium diag
  [✔] Steam Client                                  : Running (PID: 12345)
  [✔] Millennium Binary Version                     : v2.x.x (stable channel) - Verified Healthy
  [✔]     - Hook (ubuntu12_32)                      : Active and Verified
  [✔] Systemd Auto-Update Timer                     : Enabled and Active
  [✔] Sudoers Passwordless Update Authorization     : Active & Verified
```

---

## Features

- **Cross-platform** — Feature parity between Linux/Unix (Bash) and Windows (PowerShell)
- **Unified dispatcher** — `millennium <command>` alongside individual binaries
- **Guided install** — Interactive wizard for channel, background updates, and optional GitHub PAT
- **Scheduled updates** — `systemd` user timer (Linux) or Task Scheduler (Windows)
- **Secure elevation** — `/etc/sudoers.d/` drop-in (Linux) or UAC / `RunAs` (Windows)
- **Stable & beta channels** — Switch release tracks without reinstalling helpers
- **Repair & doctor** — Ownership fixes, cache purge, hook repair, self-update
- **MCP server** — Expose the suite as tools for AI assistants ([guide](docs/mcp.md))

---

## Installation

### Linux / macOS

| Method | Command |
| --- | --- |
| **curl (recommended)** | `curl -fsSL https://raw.githubusercontent.com/bolens/millenium-helpers/main/install.sh \| bash -s -- install` |
| Clone | `git clone … && sudo ./install.sh` |
| Nix | `nix run github:bolens/millenium-helpers -- --help` |
| Homebrew | `brew tap bolens/millenium-helpers https://github.com/bolens/millenium-helpers && brew install millennium-helpers` |
| Arch (local PKGBUILD) | `cd packaging && makepkg -si` |

<details>
<summary>Prerequisites & details</summary>

**Prerequisites:** `curl`, `tar`, `awk`, `sha256sum`, `unzip`, `sudo`/`visudo`, and `systemd` or `cron` for scheduling.

**Clone install** launches an interactive configuration wizard (channel, background updates, optional GitHub PAT). Non-interactive:

```bash
sudo ./install.sh install
```

**Nix profile install:**

```bash
nix profile install github:bolens/millenium-helpers
```

**Homebrew** (formula at `Formula/millennium-helpers.rb`; hashes filled after a release tag):

```bash
# From a local checkout
brew install --formula ./Formula/millennium-helpers.rb

# Or tap this repo, then install
brew tap bolens/millenium-helpers https://github.com/bolens/millenium-helpers
brew install millennium-helpers
```

Uninstall with `brew uninstall millennium-helpers` (see [Manual Uninstall](docs/uninstall_dryrun.md#4-macos--linux-homebrew-install)).

**Daily auto-updater** — run as your normal user (no `sudo`):

```bash
millennium-schedule enable [stable|beta]
```

**Arch packaging** — PKGBUILD recipes in [`packaging/`](packaging/) (`millennium-helpers-git` installs to `/usr/bin/`, completions, and sudoers for `%wheel`).

</details>

### Windows

| Method | Command |
| --- | --- |
| **irm (recommended)** | `irm https://raw.githubusercontent.com/bolens/millenium-helpers/main/scripts/windows/install.ps1 \| iex` |
| Clone | `powershell -ExecutionPolicy Bypass -File .\scripts\windows\install.ps1` |
| Scoop | `scoop install https://raw.githubusercontent.com/bolens/millenium-helpers/main/packaging/scoop/millennium-helpers.json` |
| Winget | `winget install bolens.millenniumhelpers` |

<details>
<summary>Prerequisites & details</summary>

**Prerequisites:** PowerShell 5.1+ (Windows 10/11) or PowerShell 7+. Allow script execution if needed:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

The installer:

1. Copies helpers to `$HOME/.millennium-helpers/bin`
2. Generates `.cmd` wrappers (`millennium-diag`, `millennium-upgrade`, …)
3. Adds the bin directory to your user `PATH`

Then configure scheduling and channels:

```powershell
millennium-schedule setup
```

Uninstall:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install.ps1 -Uninstall
```

**Winget:** end users install with `winget install bolens.millenniumhelpers` (community package). To try the manifests from this repo **before** they are in the winget community repository — for example while polishing a PR — clone the repo and run:

```powershell
winget install --manifest packaging/winget/
```

That path only loads the YAML in `packaging/winget/`; it is not the normal install command.

</details>

---

## Commands

Most commands are identical on Linux and Windows. Flag casing differs where noted (`--share` vs `-Share`).

| Task | Command |
| --- | --- |
| Diagnostics | `millennium-diag` |
| Share sanitized report | `millennium-diag --share` / `-Share` |
| Auto-repair (`doctor`) | `millennium-diag doctor` (alias: `--fix` / `-f`) |
| Force all repairs | `millennium-diag doctor --force` |
| Scheduler status | `millennium-schedule status` |
| Enable / disable updates | `millennium-schedule enable` · `disable` |
| Repair install | `sudo millennium-repair` / `millennium-repair` (Admin) |
| Purge Millennium | `sudo millennium-purge` / `millennium-purge` (Admin); skip prompts with `-y` / `-Yes` |
| Uninstall helpers (Linux) | `sudo ./install.sh uninstall` |

Also available via the dispatcher: `millennium diag`, `millennium doctor`, `millennium upgrade`, etc.

### Script overview

| Command | Role |
| --- | --- |
| [`install.sh`](install.sh) | Linux/macOS installer — binaries, completions, sudoers |
| [`millennium-diag`](scripts/millennium-diag.sh) | Health checks, doctor, logs, pastebin share |
| [`millennium-upgrade`](scripts/millennium-upgrade.sh) | Download, verify, install; `--force`, `--rollback` |
| [`millennium-schedule`](scripts/millennium-schedule.sh) | Daily timers / Task Scheduler |
| [`millennium-repair`](scripts/millennium-repair.sh) | Permissions, CEF cache, theme refresh |
| [`millennium-purge`](scripts/millennium-purge.sh) | De-register and remove Millennium from Steam |
| [`millennium-theme`](scripts/millennium-theme.sh) | List, install, update, remove skins |
| [`millennium-mcp`](scripts/millennium-mcp.py) | MCP server for AI assistants |
| [`millennium`](scripts/millennium.sh) | Thin dispatcher → the commands above |

Windows counterparts live under [`scripts/windows/`](scripts/windows/).

---

## Configuration

### Environment variables

| Variable | Description |
| --- | --- |
| `GITHUB_TOKEN` | Optional GitHub PAT for API auth (avoids rate limits) |
| `XDG_CONFIG_HOME` | Linux config root (default `~/.config`) |
| `LOCALAPPDATA` | Windows config root (`%LOCALAPPDATA%\millennium-helpers`) |
| `NO_COLOR` | Disable ANSI colors when set |
| `FORCE_COLOR` | Force ANSI colors even when stdout is not a TTY |
| `MILLENNIUM_QUIET` | Suppress info logs (warnings/errors still print) |
| `MILLENNIUM_DEBUG` | Windows: verbose Steam path resolution |

### Config file

Prefer a JSON file over env vars:

- **Linux:** `${XDG_CONFIG_HOME:-~/.config}/millennium-helpers/config.json`
- **Windows:** `%LOCALAPPDATA%\millennium-helpers\config.json`

Created by `millennium-schedule setup`:

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
| `update_channel` | string | `stable` or `beta` |
| `github_token` | string | Optional PAT (same role as `GITHUB_TOKEN`) |
| `backup_limit` | number | Max upgrade backups to keep |
| `backup_max_age_days` | number | Optional max age (days) for backups |

Manage with `millennium-schedule config list|get|set`. File mode is set to `600` (owner read/write only).

### Shell completions (Linux)

The installer deploys completions for:

- **Bash** → `/usr/share/bash-completion/completions/`
- **Zsh** → `/usr/share/zsh/site-functions/` (needs `compinit` in `~/.zshrc`)
- **Fish** → `/usr/share/fish/vendor_completions.d/`
- **Nushell** → `/usr/share/nushell/completions/` or `/usr/local/share/nushell/completions/`

---

## Further reading

| Topic | Doc |
| --- | --- |
| Dry-run & manual uninstall | [docs/uninstall_dryrun.md](docs/uninstall_dryrun.md) |
| MCP server setup & tools | [docs/mcp.md](docs/mcp.md) |
| Security & troubleshooting | [docs/security_troubleshooting.md](docs/security_troubleshooting.md) |
| Steam Deck & Flatpak | [docs/steam_deck.md](docs/steam_deck.md) |

Manual pages ship with the helpers (`man millennium-diag`, `man millennium-upgrade`, …) via `install.sh`, Homebrew, and packaging recipes.

---

## Development

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
make setup      # install shellcheck + ruff
make check-all  # lint + full test suite
```

Helpers report version via `--version` / `-V` (from the repo `VERSION` file). A Dev Container and Nix `devShell` are available for a reproducible environment.

---

## License

MIT — see [LICENSE](LICENSE).
