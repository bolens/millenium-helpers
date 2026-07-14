# Contributing to Millennium Helpers

Thanks for contributing. This repo provides cross-platform CLI helpers for [Millennium](https://github.com/SteamClientHomebrew/Millennium) (Steam Client homebrew). The GitHub repo is spelled `millenium-helpers` intentionally; the product name remains **Millennium**.

## Quick start

```bash
git clone https://github.com/bolens/millenium-helpers.git
cd millenium-helpers
make setup      # installs shellcheck + ruff via your package manager
make check-all  # shellcheck + ruff + full test suite
```

Alternatives:
- **Dev Container**: open the repo in a container (PowerShell, Docker-in-Docker, shellcheck, ruff, zsh/fish/nushell, Pester). Then run `make check-all`.
- **Nix**: `nix develop` for a shell with bash, python, shellcheck, and ruff (does **not** include `pwsh` or Docker).
- **Windows Pester**: `make test-windows` (requires PowerShell 7+ / `pwsh`).

## Development requirements

Tools fall into three tiers. Install what matches the work you are doing.

### Core (needed for `make check-all`)

| Tool | Used for | Install notes |
| --- | --- | --- |
| Bash 4+ (3.2 OK on macOS for scripts under test) | Running scripts and `tests/run_tests.sh` | System shell |
| `make` | Local targets | Usually via build-essential / Xcode CLT |
| `git` | Clone, hooks, PKGBUILD pkgver | System package |
| Python 3 | MCP server, packaging YAML checks, some tests | `python3` + PyYAML for `make check-winget` |
| [ShellCheck](https://www.shellcheck.net/) | `make lint` | `make setup`, or brew/pacman/apt/dnf |
| [Ruff](https://docs.astral.sh/ruff/) | Lint/format `millennium-mcp.py` | `make setup`, or brew/pacman/apt/dnf |
| `jq`, `curl`, `unzip` | Script runtime + tests | System packages |

`make setup` only installs **shellcheck** and **ruff**. Everything else above is assumed present on a normal Linux/macOS/devcontainer host.

### Recommended (full local parity with CI)

| Tool | Used for | Install notes |
| --- | --- | --- |
| **PowerShell 7+ (`pwsh`)** | `make test-windows`, Windows script work | [Install PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell); Dev Container feature includes it |
| **Pester** | Windows unit tests | `Install-Module Pester -Scope CurrentUser` (Dev Container post-create does this) |
| **zsh**, **fish**, **Nushell (≥ 0.114)** | Completion syntax/runtime smokes in `make check-completions` / CI completions workflow | Distro packages or [Nushell releases](https://www.nushell.sh/); missing shells are skipped with a warning, not a hard fail |
| `gh` | Release runbook / inspecting Actions | [GitHub CLI](https://cli.github.com/) |
| `pre-commit` | Optional git hooks | `pip install pre-commit && pre-commit install && pre-commit install --hook-type pre-push` |
| `actionlint` | Workflow lint (pre-commit) | [actionlint releases](https://github.com/rhysd/actionlint/releases) or distro/`go install`; skipped if missing |
| `gitleaks` | Secret scan (pre-commit) | [gitleaks](https://github.com/gitleaks/gitleaks); skipped if missing (`detect-private-key` from pre-commit-hooks still runs) |

### Optional (release / cross-distro)

| Tool | Used for | Install notes |
| --- | --- | --- |
| **Docker** | `make test-debian` / `test-ubuntu` / `test-fedora` / `test-all-distros` | Docker Engine or Docker Desktop; Dev Container enables Docker-in-Docker |
| `mandoc` | Local man-page lint (also in CI) | Distro package |

### What each environment provides

| Environment | Core lint/test | `pwsh` + Pester | Docker distro matrix | Extra shells (zsh/fish/nu) |
| --- | --- | --- | --- | --- |
| Host + `make setup` | Yes (after deps) | Manual | Manual | Manual |
| **Dev Container** (`.devcontainer/`) | Yes | Yes | Yes (DinD) | Yes |
| **`nix develop`** | Yes (shellcheck/ruff) | No | No | No |

Before a release, follow [docs/release_runbook.md](docs/release_runbook.md): at minimum `make lint`, `make test`, and `make test-windows`; use `make test-all-distros` when Docker is available.

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting and [docs/security_troubleshooting.md](docs/security_troubleshooting.md) for design notes. Full docs index: [docs/README.md](docs/README.md).

## Documentation

Guide index: **[docs/README.md](docs/README.md)**. When adding or renaming a guide, update that index, [README § Further reading](README.md#further-reading), topical **Related** footers, and run `make check-docs`.

| Doc | When to read |
| --- | --- |
| [docs/release_runbook.md](docs/release_runbook.md) | Cutting a release |
| [docs/licensing.md](docs/licensing.md) | Attribution / Millennium client MIT |
| [docs/mcp.md](docs/mcp.md) | MCP tool surface |
| [docs/security_troubleshooting.md](docs/security_troubleshooting.md) | Sudoers / scheduler / doctor FAQs |
| [docs/steam_deck.md](docs/steam_deck.md) | Deck / Flatpak |
| [docs/uninstall_dryrun.md](docs/uninstall_dryrun.md) | Dry-run and manual uninstall |

## Project layout

| Path | Role |
| --- | --- |
| `install.sh` | Linux/macOS installer / uninstall |
| `scripts/*.sh` | Linux/macOS user-facing command entrypoints |
| `scripts/common.sh` | Shared Bash entry (locale + sources `scripts/lib/*`) |
| `scripts/lib/` | Shared + feature libraries (`logging`, `steam`, `diag_*`, `schedule_*`, `theme_ops`, `upgrade_*`, `repair_ops`, `purge_ops`, `dispatcher`, …) |
| `scripts/windows/*.ps1` | Windows PowerShell command entrypoints |
| `scripts/windows/common.ps1` | Shared PowerShell entry (culture/colors + sources `scripts/windows/lib/*`) |
| `scripts/windows/lib/` | Shared + feature libraries (`Logging`, `Steam`, `Diag*`, `Schedule*`, `ThemeOps`, `PurgeOps`, `Dispatcher`, …) |
| `scripts/millennium-mcp.py` | MCP server for AI assistants |
| `man/` | Manual pages (`millennium-*.1`) for every user-facing command |
| `docs/` | User/maintainer guides (index: [`docs/README.md`](docs/README.md)) |
| `Formula/` | Homebrew formula (`millennium-helpers.rb`) |
| `completions/` | Bash / Zsh / Fish / Nushell / PowerShell completions |
| `tests/` | Unit + behavioral suites (`tests/run_tests.sh`) |
| `tests/windows/` | Pester tests for PowerShell scripts (`make test-windows`) |

**No thin aggregators.** Feature modules are sourced (or dot-sourced) directly by the command entrypoint or by `common.sh` / `common.ps1`. Do not add pass-through-only loader files that only re-source other modules.

## Adding or changing a command

1. Implement the change in the Linux/macOS script under `scripts/` (and the Windows `.ps1` when applicable).
2. Keep `--help` / `-h` accurate and exit `0` on help.
3. On unknown options, print usage and exit non-zero.
4. Update matching files under `completions/` so flags stay in sync.
5. Keep `man/millennium-<name>.1` in sync (`.TH` date like `"July 9, 2026"`; `make check-man` / CI mandoc lint).
6. Add or extend behavioral tests under `tests/behavioral/` (and Pester under `tests/windows/` for PowerShell).
7. Prefer `--dry-run` for destructive paths; require confirmation (or `-y`/`--yes`) for irreversible actions like purge.

## Linux / Windows parity

When adding a feature, check both platforms. Document intentional gaps in the PR. Rough checklist:

- [ ] Flag / subcommand exists on both OSes (or noted as Linux-only / Windows-only)
- [ ] Dry-run behavior matches
- [ ] Help text documents the same options
- [ ] Tests cover the new path on at least one platform; prefer both when practical

## Testing

See [Development requirements](#development-requirements) for tools each target needs.

```bash
make test              # local Bash unit + behavioral suite
make lint              # shellcheck + ruff (+ version/man/docs/completions gates)
make check-all         # lint + test
make test-windows      # Pester under tests/windows/ (requires pwsh)
make test-all-distros  # local + Debian/Ubuntu/Fedora via Docker (requires Docker)
```

## Versioning

`VERSION` at the repo root is the helpers package version (aligned with Scoop, Winget,
Homebrew, versioned Arch, Nix release package, and `pyproject.toml`). Installers copy it
next to the shared libraries so `--version` / `-Version` work after install. Prefer git
tags `vX.Y.Z` that match `VERSION`.

Tip-of-main packages (`packaging/millennium-helpers-git`, Scoop `millennium-helpers-git`,
Winget `bolens.millenniumhelpers.git`, Nix `#millennium-helpers-git`) are **not** tied to
`VERSION`; they track git HEAD.

### Helpers install tracks vs client channel

| Concept | Values | Where |
| --- | --- | --- |
| **Helpers track** | `release` (default), `main`, `tag`, `checkout` | `install-meta.json`; `install.sh --track` / `--tag`; `install.ps1 -Track` / `-Tag` |
| **Client channel** | `stable`, `beta`, `main` | `config.json` → `update_channel`; `millennium-upgrade --channel`; schedule enable |

Doctor syncs helpers against the recorded track (pinned tags stay pinned). Legacy installs without meta are auto-migrated on first install/diag/doctor touch.

### Make targets

| Target | Script | Purpose |
| --- | --- | --- |
| `make bump-version VERSION=X.Y.Z` | `scripts/ci/bump-version.sh` | Pre-tag bump: write `VERSION` + packaging **versions/URLs**; **keep existing hashes**; regenerate stable Arch `.SRCINFO`; run `check-version` |
| `make check-version` | `scripts/ci/check-version-sync.sh` | Assert packaging version strings + release-asset URL shape match `VERSION` (also runs inside `make lint`) |
| `make sync-stable-srcinfo` | `scripts/ci/sync-stable-srcinfo.sh` | Regenerate `packaging/millennium-helpers/.SRCINFO` from `PKGBUILD` (`--check` fails if stale) |
| `make sync-git-srcinfo` | `scripts/ci/sync-git-srcinfo.sh` | Regenerate Arch `-git` `.SRCINFO` when the recipe changes (`pkgver` drift ignored; `pkgver()` owns the version at build time) |

Post-tag (release CD only): `scripts/ci/update-packaging-versions.sh <ver> <linux_sha> <windows_sha>`
fills real SHA256s / SRI hashes for Formula, Scoop, Winget, versioned Arch, and Nix.

### Pre-tag bump (preferred)

```bash
make bump-version VERSION=X.Y.Z
# edit CHANGELOG.md under ## [X.Y.Z] - YYYY-MM-DD  (manual)
make check-version   # already run by bump-version; safe to re-run
```

`bump-version` updates:

- `VERSION`, `pyproject.toml`
- Formula / Scoop / Winget release URLs + version fields (`ReleaseDate` on Winget installer)
- `packaging/millennium-helpers/PKGBUILD` (`pkgver`, `pkgrel=1`) and `.SRCINFO`
- `nix/release-info.nix` **version only** (`srcHash` unchanged until assets exist)

It does **not** edit `CHANGELOG.md`. Do **not** hand-edit `.SRCINFO` — use `bump-version` or
`make sync-stable-srcinfo`.

Before the tag exists, Nix/Arch CI may **skip** building the release tarball package (asset
404); that is expected. Tip-of-main / `-git` builds still run.

### What `check-version` validates

- `pyproject.toml` `version`
- Scoop release manifest `version` + Windows zip URL shape
- Winget `PackageVersion` on all three manifests + installer URL shape
- Homebrew Formula version (from URL or explicit `version`) + Linux tarball URL shape
- Versioned Arch `PKGBUILD` `pkgver` + Linux tarball URL shape
- Versioned Arch `.SRCINFO` in sync with `PKGBUILD` (via `sync-stable-srcinfo --check`)
- `nix/release-info.nix` `version`

Placeholder / previous-release checksums are allowed; version strings and URL **shape** must
match. Tip-of-main / `-git` packages are excluded.

### Cutting a release

Follow [docs/release_runbook.md](docs/release_runbook.md) end-to-end (local `make lint` /
`make test` / `make test-windows`, `make bump-version`, CI green, then tag). Do not tag until
ShellCheck and the test suite pass locally and on `main`.

Tagging `vX.Y.Z` runs the release workflow:

1. Wait for **Test Suite + ShellCheck + Completions** on that commit
2. Draft a GitHub release with platform-trimmed assets (`millennium-helpers-linux.tar.gz`, `millennium-helpers-windows.zip`) plus checksum sidecars
3. Open a packaging PR that points Formula / Scoop / Winget at those release assets and fills SHA256s from the draft upload
4. **If packaging CI passes:** squash-merge the PR and publish the draft release automatically
5. **If packaging CI fails (or never starts):** leave the draft release and packaging PR for manual recovery (fix, merge, then publish)

Piped installers (`install.sh` / `install.ps1`) download the **latest published** trimmed release asset (override with `MILLENNIUM_HELPERS_RELEASE_URL`).

Repo secret `PACKAGING_PAT` is **required** for the automatic path: a classic PAT with `contents` + `pull-requests`, and permission to merge into `main` under any branch protection. PRs opened with `GITHUB_TOKEN` do not trigger workflows, so without this secret the finalize job cannot wait on packaging CI.

Local checks:
```bash
make check-version         # VERSION ↔ packaging (see Versioning above)
make bump-version VERSION=X.Y.Z   # pre-tag bump (then edit CHANGELOG)
make sync-stable-srcinfo   # regenerate versioned Arch .SRCINFO only
make sync-git-srcinfo      # regenerate -git .SRCINFO after recipe edits
make check-man             # every command has a man page
make check-docs            # docs index / Related footers / man / licensing cross-links
make check-licensing       # alias for check-docs
make check-winget          # Winget manifest structure (docs-only; no winget validate)
```

Optional local hooks (see `.pre-commit-config.yaml`):

```bash
pip install pre-commit   # if needed
pre-commit install
pre-commit install --hook-type pre-push
```

**pre-commit** runs: remote [pre-commit-hooks](https://github.com/pre-commit/pre-commit-hooks) sanity checks (private keys, merge conflicts, large files, symlinks, trailing whitespace, EOF newlines, LF line endings), plus local shellcheck, ruff check + format `--check`, VERSION presence, versioned Arch `.SRCINFO` sync, Arch `-git` `.SRCINFO` sync when that recipe changes, packaging version sync, winget manifests, completions tests (when `completions/` changes), man-page coverage, docs cross-links (guides + licensing), actionlint (workflows; skipped if not installed), and gitleaks on staged changes (skipped if not installed).

**pre-push** runs: `make lint`, and `make test-windows` when the push range touches `scripts/windows/`, `tests/windows/`, or `completions/powershell/` (skipped if `pwsh` is missing).

## Style

- Bash: `set -euo pipefail`; source `common.sh` / `scripts/lib/*` rather than duplicating helpers.
- macOS ships Bash 3.2: under `set -u`, empty `"${arr[@]}"` / `"${arr[*]}"` is unbound. Prefer `${arr[@]+"${arr[@]}"}` (or a length guard) when an array may be empty. Avoid `"${arr[@]:-}"` (it iterates once with an empty value).
- Honor `NO_COLOR` (and `FORCE_COLOR` when forcing color).
- PowerShell: `Set-StrictMode -Version Latest`; gate debug noise behind `MILLENNIUM_DEBUG` or `-Verbose`.
- Do not commit packaging build artifacts (`packaging/*.pkg.tar.zst`, etc.).
- Do **not** bump Arch `-git` `pkgver` on every commit ([AUR VCS policy](https://wiki.archlinux.org/title/AUR_submission_guidelines)). `pkgver()` recalculates at `makepkg` time; regenerate `.SRCINFO` only when the `-git` recipe changes (`make sync-git-srcinfo`).
- Keep versioned Arch `.SRCINFO` current with `make sync-stable-srcinfo` (or `make bump-version`). Pre-commit regenerates it when the stable PKGBUILD changes.

## Packaging notes

- Homebrew / Scoop (release) / Winget / Nix `millennium-helpers` consume the **trimmed GitHub Release assets**, not the auto-generated source archives.
- Homebrew Formula version is taken from the `releases/download/vX.Y.Z/…` URL. Do **not** add a redundant `version "X.Y.Z"` line — `brew audit` rejects it. Keep `license "MIT"`.
- Scoop is the supported multi-command Windows install path (`millennium`, `millennium-mcp`, and the individual commands).
- Scoop `millennium-helpers-git` is a nightly tip-of-`main` install (GitHub archive); it is outside the versioned release bump.
- Nix `packages.millennium-helpers` uses the Linux release tarball (`nix/release-info.nix`); `packages.millennium-helpers-git` builds from the flake source (commit in the version string). Default package is the release build.
- Winget release manifests track the Windows zip URL/hash for documentation only. Tip-of-main manifests are under `packaging/winget-git/` and are not VERSION-gated. WinGet portable nested files allow `.exe` only, so these PowerShell scripts cannot pass `winget validate` as a multi-command portable package.
- `scripts/ci/bump-version.sh` — pre-tag version/URL bump (keeps hashes); prefer `make bump-version VERSION=X.Y.Z`.
- `scripts/ci/check-version-sync.sh` — packaging ↔ `VERSION` gate; prefer `make check-version` (also part of `make lint`).
- `scripts/ci/sync-stable-srcinfo.sh` — regenerate or `--check` versioned Arch `.SRCINFO`; prefer `make sync-stable-srcinfo`.
- `scripts/ci/sync-git-srcinfo.sh` — regenerate or `--check` Arch `-git` `.SRCINFO` (ignores `pkgver` drift); prefer `make sync-git-srcinfo`.
- `scripts/ci/update-packaging-versions.sh` — post-tag: Formula / Scoop release / Winget / versioned Arch / Nix release-info from a release tag + asset hashes (release CD).
- Versioned Arch (`packaging/millennium-helpers`) is bumped with Formula / Scoop / Winget on release (Linux tarball URL + sha256). Arch `-git` stays tip-of-main and is outside that bump; do not commit mere `-git` `pkgver` bumps.
- Man-page CI (`scripts/ci/check-man-pages.sh`) fails on mandoc `ERROR`/`FATAL` only; `WARNING`/`STYLE` are printed as notes.
- Docs CI (`scripts/ci/check-docs-crosslinks.sh`) — docs index, Related footers, man→guide links, and licensing attribution; prefer `make check-docs` (`make check-licensing` is an alias).
- Release Linux/Windows assets **must** include `third_party/MILLENNIUM-LICENSE.md` (see [docs/licensing.md](docs/licensing.md) and `make check-docs`).

## Licensing

Helpers are MIT ([`LICENSE`](LICENSE)). The Millennium **client** is a separate MIT project — see **[docs/licensing.md](docs/licensing.md)** (canonical), [`third_party/MILLENNIUM-LICENSE.md`](third_party/MILLENNIUM-LICENSE.md), and [upstream `LICENSE.md`](https://github.com/SteamClientHomebrew/Millennium/blob/main/LICENSE.md).

When changing attribution, the vendored notice, upgrade license installation, man-page `LICENSE` sections, Winget descriptions, or release payload contents:

1. Update [docs/licensing.md](docs/licensing.md) and [README § License](README.md#license).
2. Keep `third_party/README.md` and man-page `LICENSE` sections pointing at the hub.
3. Run `make check-docs` (included in `make lint` / `make check-all`).

## Pull requests

- Keep PRs focused; include a short summary and test plan.
- Mention any completion, man-page, or docs updates.
- CI must pass (multi-distro + macOS test matrix, ShellCheck, Ruff, man pages, Homebrew audit, completions, packaging checks).
