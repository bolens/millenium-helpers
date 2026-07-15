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
```

```powershell
# Install (Windows) — Scoop recommended, or download the Go binary and install:
scoop install https://raw.githubusercontent.com/bolens/millenium-helpers/main/packaging/scoop/millennium-helpers-bin.json
# Or: winget install bolens.millenniumhelpers
```

Then use the Go CLI (`millennium <command>`):

```bash
millennium diag                 # health check
millennium doctor               # auto-repair
millennium upgrade              # install / update Millennium
millennium schedule enable      # daily background updates (Linux)
millennium theme list           # manage skins
millennium mcp                  # MCP server for AI assistants
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

- **Go CLI** — One `bin/millennium` binary owns schedule, theme, diag/doctor, upgrade, purge, repair, and MCP on Linux and Windows
- **Single PATH entry** — New installs put only `millennium` on PATH (`millennium <cmd>…`); leftover long-name argv0 twins still dispatch if present
- **Guided install** — Interactive wizard for Millennium **client** channel, background updates, and optional GitHub PAT (helpers **track** is set separately with `--track` / `-Track`)
- **Scheduled updates** — `systemd` (system/user), launchd/cron, or Task Scheduler; timers call `millennium …`
- **Secure elevation** — `/etc/sudoers.d/` drop-in (Linux) or UAC / `RunAs` (Windows)
- **Stable, beta & main client channels** — Switch Millennium client update channel without reinstalling helpers
- **Repair & doctor** — Ownership fixes, cache purge, hook repair, self-update
- **MCP server** — Built-in Go stdio MCP (`millennium mcp` / `millennium-mcp`) for AI assistants ([guide](docs/mcp.md))
- **Packaging matrix** — from-source / `-bin` / `-git` for Arch, Homebrew, Scoop, Nix; plus deb, rpm, Chocolatey, Winget ([packaging/README.md](packaging/README.md))

---

## Installation

### Linux / macOS

| Method | Command |
| --- | --- |
| **curl (recommended)** | `curl -fsSL https://raw.githubusercontent.com/bolens/millenium-helpers/main/install.sh \| bash -s -- install` |
| curl (tip of `main`) | `curl -fsSL …/install.sh \| bash -s -- install --track main` |
| curl (pinned tag) | `curl -fsSL …/install.sh \| bash -s -- install --tag v3.0.0` |
| Clone | `git clone … && sudo ./install.sh` (needs Go, or a release tree with `bin/millennium`) |
| Nix (from-source) | `nix profile install github:bolens/millenium-helpers` |
| Nix (prebuilt `-bin`) | `nix profile install github:bolens/millenium-helpers#millennium-helpers-bin` |
| Nix (tip of flake / `-git`) | `nix profile install github:bolens/millenium-helpers#millennium-helpers-git` |
| Homebrew (from-source) | `brew tap bolens/millenium-helpers https://github.com/bolens/millenium-helpers && brew install millennium-helpers` |
| Homebrew (prebuilt `-bin`) | `brew install millennium-helpers-bin` (conflicts with `millennium-helpers`) |
| Arch (from-source) | `cd packaging/millennium-helpers && makepkg -si` |
| Arch (`-bin`) | `cd packaging/millennium-helpers-bin && makepkg -si` |
| Arch (`-git`) | `cd packaging/millennium-helpers-git && makepkg -si` |
| deb (from-source) | `packaging/deb/build-from-source.sh && sudo dpkg -i dist/millennium-helpers_*.deb` |
| deb (`-bin`) | `packaging/deb/build-bin.sh && sudo dpkg -i dist/millennium-helpers-bin_*.deb` |
| rpm (from-source) | `rpmbuild -bb packaging/rpm/millennium-helpers.spec` |
| rpm (`-bin`) | `rpmbuild -bb packaging/rpm/millennium-helpers-bin.spec` |

Full packaging matrix (variants per channel): [packaging/README.md](packaging/README.md).

<details>
<summary>Prerequisites & details</summary>

**Prerequisites:** `curl`, `tar`, `awk`, `sha256sum`, `unzip`, `sudo`/`visudo`, and `systemd` or `cron` for scheduling.

**Clone install** launches an interactive configuration wizard (Millennium **client** channel, background updates, optional GitHub PAT). Helpers install **track** (`release` / `main` / `tag`) is separate — set with `--track` / `--tag` on the installer. Non-interactive:

```bash
sudo ./install.sh install
# Tip-of-main helpers:
sudo ./install.sh install --track main
# Pin helpers to a release tag:
sudo ./install.sh install --tag v3.0.0
```

Install requires the Go dispatcher (`bin/millennium`) — present in release/from-source
archives, or built via `make build` when installing from a checkout.

**Nix profile install** (from-source by default; `-bin` / `-git` as flake packages):

```bash
nix profile install github:bolens/millenium-helpers
nix profile install github:bolens/millenium-helpers#millennium-helpers-bin
nix profile install github:bolens/millenium-helpers#millennium-helpers-git
# Or pin a tag: nix profile install github:bolens/millenium-helpers/v3.0.0
```

**Homebrew** (formulas at `Formula/millennium-helpers.rb` and
`Formula/millennium-helpers-bin.rb`; hashes filled after a release tag):

```bash
# From a local checkout
brew install --formula ./Formula/millennium-helpers.rb

# Or tap this repo, then install from-source or prebuilt:
brew tap bolens/millenium-helpers https://github.com/bolens/millenium-helpers
brew install millennium-helpers
# brew install millennium-helpers-bin
```

Uninstall with `brew uninstall millennium-helpers` (see [Manual Uninstall](docs/uninstall_dryrun.md#4-macos--linux-homebrew-install)).

**Daily auto-updater** — run as your normal user (no `sudo`):

```bash
millennium schedule enable [stable|beta|main]
```

**Arch packaging** — PKGBUILD recipes in [`packaging/millennium-helpers/`](packaging/millennium-helpers/) (from-source), [`packaging/millennium-helpers-bin/`](packaging/millennium-helpers-bin/) (release tarball), and [`packaging/millennium-helpers-git/`](packaging/millennium-helpers-git/) (tip of `main`). Each installs to `/usr/bin/`, completions, and sudoers for `%wheel`.

**deb / rpm** — build scripts and specs under [`packaging/deb/`](packaging/deb/) and [`packaging/rpm/`](packaging/rpm/). From-source builds require Go + `make build`; `-bin` packages pull the published Linux release tarball after a tag.

</details>

### Windows

| Method | Command |
| --- | --- |
| **Scoop (prebuilt `-bin`, recommended)** | `scoop install https://raw.githubusercontent.com/bolens/millenium-helpers/main/packaging/scoop/millennium-helpers-bin.json` |
| Scoop (from-source / release) | `scoop install https://raw.githubusercontent.com/bolens/millenium-helpers/main/packaging/scoop/millennium-helpers.json` |
| Scoop (`main` / nightly) | `scoop install https://raw.githubusercontent.com/bolens/millenium-helpers/main/packaging/scoop/millennium-helpers-git.json` |
| Winget (release) | `winget install bolens.millenniumhelpers` |
| Winget (tip of `main`) | `winget install --manifest packaging/winget-git/` (local manifests; community package `bolens.millenniumhelpers.git`) |
| Chocolatey | Local: `cd packaging/chocolatey/millennium-helpers && choco pack && choco install millennium-helpers -s . -y` · published: `choco install millennium-helpers` |
| Standalone Go binary | Download `millennium-v*-windows-amd64.exe` from [Releases](https://github.com/bolens/millenium-helpers/releases/latest), then `.\millennium-v*-windows-amd64.exe install` |
| Clone | `go build -C go -o bin\millennium.exe ./cmd/millennium` then `.\bin\millennium.exe install --skip-wizard` (or omit `--skip-wizard` for the schedule setup wizard) |

<details>
<summary>Prerequisites & details</summary>

**Prerequisites:** A recent Windows 10/11 install. Packaging methods place `millennium.exe` on your `PATH`.

`millennium install`:

1. Installs `millennium.exe` under `%USERPROFILE%\.millennium-helpers\bin`
2. Adds that directory to your user `PATH`
3. Registers PowerShell completion profile hooks when a completer is present

Then configure scheduling and the Millennium **client** channel (separate from helpers `--track`):

```powershell
millennium schedule setup
# or: millennium schedule config set update_channel main
```

Uninstall:

```powershell
millennium uninstall
```

**Winget:** end users install with `winget install bolens.millenniumhelpers` (community package). Tip-of-main manifests live in [`packaging/winget-git/`](packaging/winget-git/) (`bolens.millenniumhelpers.git`, rolling `0.0.0-git`). Uninstall the release package before installing the git package (same as Scoop). To try manifests from this repo before they are in the community repository:

```powershell
winget install --manifest packaging/winget/
winget install --manifest packaging/winget-git/
```

Those `--manifest` paths only load the YAML in-repo; they are not the normal community install commands.

**Chocolatey** — bin-only package under [`packaging/chocolatey/millennium-helpers/`](packaging/chocolatey/millennium-helpers/) (downloads the Windows release zip). Tip-of-main is Scoop/Winget git, not Chocolatey. Pack and install from a checkout before the community package exists:

```powershell
cd packaging\chocolatey\millennium-helpers
choco pack
choco install millennium-helpers -s . -y
```

</details>

---

## Commands

Most commands are identical on Linux and Windows. Flag casing differs where noted (`--share` vs `-Share`).

| Task | Command |
| --- | --- |
| Diagnostics | `millennium diag` |
| Share sanitized report | `millennium diag --share` / `-Share` |
| Auto-repair (`doctor`) | `millennium doctor` (or `millennium diag doctor`; `--fix` / `-f`) |
| Force all repairs | `millennium doctor --force` |
| Scheduler status | `millennium schedule status` |
| Enable / disable updates | `millennium schedule enable` · `disable` |
| Repair install | `sudo millennium repair` / `millennium repair` (Admin) |
| Purge Millennium | `sudo millennium purge` / `millennium purge` (Admin); skip prompts with `-y` / `-Yes` |
| Uninstall helpers | `sudo millennium uninstall` (Unix) · `millennium uninstall` (Windows) |

New installs put only `millennium` / `millennium.exe` on PATH. Prefer
`millennium <command>` (leftover long-name argv0 twins still work if present).

### Command overview

| Entry | Role |
| --- | --- |
| [`millennium`](go/cmd/millennium) | Go CLI (`bin/millennium` / `millennium.exe`) — all features below |
| `millennium diag` / `doctor` | Health checks, doctor, logs, pastebin share |
| `millennium upgrade` | Download, verify, install; `--force`, `--rollback` |
| `millennium schedule` | Timers / Task Scheduler + config / setup |
| `millennium repair` | Permissions, CEF cache, theme refresh |
| `millennium purge` | De-register and remove Millennium from Steam |
| `millennium theme` | List, install, update, remove skins |
| `millennium mcp` | MCP server for AI assistants ([docs/mcp.md](docs/mcp.md)) |
| `millennium install` / `uninstall` | Install helpers (Go); thin [`install.sh`](install.sh) on Unix; Windows via Scoop/Winget/standalone `millennium.exe` |

Feature commands ship as the Go CLI only. Contract and OS coverage:
[`spec/cli-contract.yaml`](spec/cli-contract.yaml) and
[`.github/workflows/go.yml`](.github/workflows/go.yml).

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

Created by `millennium schedule setup`:

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

Manage with `millennium schedule config list|get|set`. File mode is set to `600` (owner read/write only).

### Shell completions

**Linux / macOS** — the installer deploys completions for:

- **Bash** → `/usr/share/bash-completion/completions/`
- **Zsh** → `/usr/share/zsh/site-functions/` (needs `compinit` in `~/.zshrc`)
- **Fish** → `/usr/share/fish/vendor_completions.d/`
- **Nushell** → `/usr/share/nushell/completions/` or `/usr/local/share/nushell/completions/`

**Windows** — `millennium install` installs [`completions/powershell/millennium-helpers.ps1`](completions/powershell/millennium-helpers.ps1) as `~/.millennium-helpers/bin/millennium-helpers.completion.ps1` and registers a PowerShell profile hook. Restart the terminal (or dot-source the completer) for Tab completion on `millennium`.

---

## Further reading

| Topic | Doc |
| --- | --- |
| Documentation index | [docs/README.md](docs/README.md) |
| Licensing (helpers + Millennium) | [docs/licensing.md](docs/licensing.md) |
| CLI contract (commands / flags / MCP) | [spec/cli-contract.yaml](spec/cli-contract.yaml) |
| Packaging matrix (from-source / bin / git) | [packaging/README.md](packaging/README.md) |
| Dry-run & manual uninstall | [docs/uninstall_dryrun.md](docs/uninstall_dryrun.md) |
| Release runbook | [docs/release_runbook.md](docs/release_runbook.md) |
| MCP server setup & tools | [docs/mcp.md](docs/mcp.md) |
| Security policy | [SECURITY.md](SECURITY.md) |
| Security & troubleshooting | [docs/security_troubleshooting.md](docs/security_troubleshooting.md) |
| Steam Deck & Flatpak | [docs/steam_deck.md](docs/steam_deck.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |

Manual pages ship with the helpers (`man millennium`, `man millennium-diag`, …) via `millennium install`, Homebrew, and packaging recipes.

---

## Development

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) (including **[development requirements](CONTRIBUTING.md#development-requirements)** and **[versioning](CONTRIBUTING.md#versioning)** for `pwsh`, Docker, ShellCheck, `make bump-version` / `make check-version`, etc.). Releases: [docs/release_runbook.md](docs/release_runbook.md).

```bash
make setup         # install shellcheck + ruff
make check-all     # lint + test-go + install-time Bash suite (feature parity is test-go / go.yml)
make test-windows  # Pester install + completions (requires PowerShell 7+ / pwsh)
make build         # Go CLI → bin/millennium (requires Go)
make test-go       # Go unit + dispatcher smokes
# make bump-version VERSION=X.Y.Z   # pre-tag packaging version bump
# make check-version               # VERSION ↔ packaging manifests
# make test-all-distros            # optional; requires Docker
```

Helpers report version via `--version` / `-V` (from the repo `VERSION` file). A Dev Container (includes `pwsh` + Docker-in-Docker) and a Nix `devShell` (lint tools only) are available for a reproducible environment. Go owns the installed CLI; feature CI is [`go.yml`](.github/workflows/go.yml) (Linux / Windows / macOS). See [CONTRIBUTING.md](CONTRIBUTING.md) for layout and install bootstrap notes.

---

## License

**Millennium Helpers** is licensed under the [MIT License](LICENSE) (Copyright © 2026 bolens).

These helpers install and manage **[Millennium](https://github.com/SteamClientHomebrew/Millennium)**, a separate project by Project Millennium / [SteamClientHomebrew](https://github.com/SteamClientHomebrew). Millennium is also MIT-licensed — see [their LICENSE.md](https://github.com/SteamClientHomebrew/Millennium/blob/main/LICENSE.md) (a local copy is in [`third_party/MILLENNIUM-LICENSE.md`](third_party/MILLENNIUM-LICENSE.md)). Installing or upgrading the Millennium client via these tools is subject to Millennium’s license terms; `millennium upgrade` places a copy of that notice next to the installed client files.

This project is not affiliated with or endorsed by SteamClientHomebrew, Project Millennium, or Valve Corporation. Steam® is a trademark of Valve Corporation.

Full details, packaging notes, and maintainer sync checklist: **[docs/licensing.md](docs/licensing.md)**.
