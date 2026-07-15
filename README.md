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
[Docs](docs/README.md)

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
- **Guided install** — Interactive wizard for Millennium **client** channel, background updates, and optional GitHub PAT (helpers **track** is set separately with `--track` / `-Track`)
- **Scheduled updates** — `systemd` user timer (Linux) or Task Scheduler (Windows)
- **Secure elevation** — `/etc/sudoers.d/` drop-in (Linux) or UAC / `RunAs` (Windows)
- **Stable, beta & main client channels** — Switch Millennium client update channel without reinstalling helpers
- **Repair & doctor** — Ownership fixes, cache purge, hook repair, self-update
- **MCP server** — Expose the suite as tools for AI assistants ([guide](docs/mcp.md))

---

## Installation

### Linux / macOS

| Method | Command |
| --- | --- |
| **curl (recommended)** | `curl -fsSL https://raw.githubusercontent.com/bolens/millenium-helpers/main/install.sh \| bash -s -- install` |
| curl (tip of `main`) | `curl -fsSL …/install.sh \| bash -s -- install --track main` |
| curl (pinned tag) | `curl -fsSL …/install.sh \| bash -s -- install --tag v2.5.0` |
| Clone | `git clone … && sudo ./install.sh` |
| Nix (release) | `nix profile install github:bolens/millenium-helpers` / `nix run github:bolens/millenium-helpers` |
| Nix (tip of flake / git) | `nix profile install github:bolens/millenium-helpers#millennium-helpers-git` |
| Homebrew | `brew tap bolens/millenium-helpers https://github.com/bolens/millenium-helpers && brew install millennium-helpers` |
| Arch (versioned PKGBUILD) | `cd packaging/millennium-helpers && makepkg -si` |
| Arch (`-git` from checkout) | `cd packaging/millennium-helpers-git && makepkg -si` |

<details>
<summary>Prerequisites & details</summary>

**Prerequisites:** `curl`, `tar`, `awk`, `sha256sum`, `unzip`, `sudo`/`visudo`, and `systemd` or `cron` for scheduling.

**Clone install** launches an interactive configuration wizard (Millennium **client** channel, background updates, optional GitHub PAT). Helpers install **track** (`release` / `main` / `tag`) is separate — set with `--track` / `--tag` on the installer. Non-interactive:

```bash
sudo ./install.sh install
# Tip-of-main helpers:
sudo ./install.sh install --track main
# Pin helpers to a release tag:
sudo ./install.sh install --tag v2.5.0
```

**Nix profile install** (release tarball by default; tip-of-flake with `#millennium-helpers-git`):

```bash
nix profile install github:bolens/millenium-helpers
nix profile install github:bolens/millenium-helpers#millennium-helpers-git
# Or pin a tag: nix profile install github:bolens/millenium-helpers/v2.4.0
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
millennium-schedule enable [stable|beta|main]
```

**Arch packaging** — PKGBUILD recipes in [`packaging/millennium-helpers/`](packaging/millennium-helpers/) (versioned release tarball) and [`packaging/millennium-helpers-git/`](packaging/millennium-helpers-git/) (tip of `main`). Both install to `/usr/bin/`, completions, and sudoers for `%wheel`.

</details>

### Windows

| Method | Command |
| --- | --- |
| **irm (recommended)** | `irm https://raw.githubusercontent.com/bolens/millenium-helpers/main/scripts/windows/install.ps1 \| iex` |
| irm (tip of `main`) | `irm …/install.ps1 \| iex` then re-run with `-Track main`, or download and `.\install.ps1 -Track main` |
| Scoop (release) | `scoop install https://raw.githubusercontent.com/bolens/millenium-helpers/main/packaging/scoop/millennium-helpers.json` |
| Scoop (`main` / nightly) | `scoop install https://raw.githubusercontent.com/bolens/millenium-helpers/main/packaging/scoop/millennium-helpers-git.json` |
| Winget (release) | `winget install bolens.millenniumhelpers` |
| Winget (tip of `main`) | `winget install --manifest packaging/winget-git/` (local manifests; community package `bolens.millenniumhelpers.git`) |
| Clone | `powershell -ExecutionPolicy Bypass -File .\scripts\windows\install.ps1` |

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

Then configure scheduling and the Millennium **client** channel (separate from helpers `-Track`):

```powershell
millennium-schedule setup
# or: millennium-schedule config set update_channel main
```

Uninstall:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install.ps1 -Uninstall
```

**Winget:** end users install with `winget install bolens.millenniumhelpers` (community package). Tip-of-main manifests live in [`packaging/winget-git/`](packaging/winget-git/) (`bolens.millenniumhelpers.git`, rolling `0.0.0-git`). Uninstall the release package before installing the git package (same as Scoop). To try manifests from this repo before they are in the community repository:

```powershell
winget install --manifest packaging/winget/
winget install --manifest packaging/winget-git/
```

Those `--manifest` paths only load the YAML in-repo; they are not the normal community install commands.

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
| [`millennium-mcp`](go/internal/mcp/) | MCP server for AI assistants (`millennium mcp`) |
| [`millennium`](go/cmd/millennium) | Go PATH dispatcher (`bin/millennium`) → the commands above |

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
| `update_channel` | string | Millennium **client** channel: `stable`, `beta`, or `main` (separate from helpers install track) |
| `github_token` | string | Optional PAT (same role as `GITHUB_TOKEN`) |
| `backup_limit` | number | Max upgrade backups to keep |
| `backup_max_age_days` | number | Optional max age (days) for backups |

Manage with `millennium-schedule config list|get|set`. File mode is set to `600` (owner read/write only).

### Shell completions

**Linux / macOS** — the installer deploys completions for:

- **Bash** → `/usr/share/bash-completion/completions/`
- **Zsh** → `/usr/share/zsh/site-functions/` (needs `compinit` in `~/.zshrc`)
- **Fish** → `/usr/share/fish/vendor_completions.d/`
- **Nushell** → `/usr/share/nushell/completions/` or `/usr/local/share/nushell/completions/`

**Windows** — `install.ps1` installs [`completions/powershell/millennium-helpers.ps1`](completions/powershell/millennium-helpers.ps1) as `~/.millennium-helpers/bin/millennium-helpers.completion.ps1` and registers a PowerShell profile hook. Restart the terminal (or dot-source the completer) for Tab completion on `millennium`, `millennium-schedule`, and the other helpers.

---

## Further reading

| Topic | Doc |
| --- | --- |
| Documentation index | [docs/README.md](docs/README.md) |
| Licensing (helpers + Millennium) | [docs/licensing.md](docs/licensing.md) |
| Bash/PS → Go unification audit | [docs/unification-audit.md](docs/unification-audit.md) |
| Unification roadmap + parity gates | [docs/unification-roadmap.md](docs/unification-roadmap.md) |
| Dry-run & manual uninstall | [docs/uninstall_dryrun.md](docs/uninstall_dryrun.md) |
| Release runbook | [docs/release_runbook.md](docs/release_runbook.md) |
| MCP server setup & tools | [docs/mcp.md](docs/mcp.md) |
| Security policy | [SECURITY.md](SECURITY.md) |
| Security & troubleshooting | [docs/security_troubleshooting.md](docs/security_troubleshooting.md) |
| Steam Deck & Flatpak | [docs/steam_deck.md](docs/steam_deck.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |

Manual pages ship with the helpers (`man millennium-diag`, `man millennium-upgrade`, …) via `install.sh`, Homebrew, and packaging recipes.

---

## Development

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) (including **[development requirements](CONTRIBUTING.md#development-requirements)** and **[versioning](CONTRIBUTING.md#versioning)** for `pwsh`, Docker, ShellCheck, `make bump-version` / `make check-version`, etc.). Releases: [docs/release_runbook.md](docs/release_runbook.md).

```bash
make setup         # install shellcheck + ruff
make check-all     # lint + full Bash test suite (lint includes check-version + cli-contract)
make test-windows  # Pester (requires PowerShell 7+ / pwsh)
make build         # Go CLI → bin/millennium (requires Go)
make test-go       # Go unit + dispatcher smokes
# make bump-version VERSION=X.Y.Z   # pre-tag packaging version bump
# make check-version               # VERSION ↔ packaging manifests
# make test-all-distros            # optional; requires Docker
```

Helpers report version via `--version` / `-V` (from the repo `VERSION` file). A Dev Container (includes `pwsh` + Docker-in-Docker) and a Nix `devShell` (lint tools only) are available for a reproducible environment. Cross-language unification (Bash/PowerShell → Go): [docs/unification-roadmap.md](docs/unification-roadmap.md).

---

## License

**Millennium Helpers** is licensed under the [MIT License](LICENSE) (Copyright © 2026 bolens).

These helpers install and manage **[Millennium](https://github.com/SteamClientHomebrew/Millennium)**, a separate project by Project Millennium / [SteamClientHomebrew](https://github.com/SteamClientHomebrew). Millennium is also MIT-licensed — see [their LICENSE.md](https://github.com/SteamClientHomebrew/Millennium/blob/main/LICENSE.md) (a local copy is in [`third_party/MILLENNIUM-LICENSE.md`](third_party/MILLENNIUM-LICENSE.md)). Installing or upgrading the Millennium client via these tools is subject to Millennium’s license terms; `millennium-upgrade` places a copy of that notice next to the installed client files.

This project is not affiliated with or endorsed by SteamClientHomebrew, Project Millennium, or Valve Corporation. Steam® is a trademark of Valve Corporation.

Full details, packaging notes, and maintainer sync checklist: **[docs/licensing.md](docs/licensing.md)**.
