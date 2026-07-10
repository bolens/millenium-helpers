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

See [SECURITY.md](SECURITY.md) for vulnerability reporting and [docs/security_troubleshooting.md](docs/security_troubleshooting.md) for design notes.

## Project layout

| Path | Role |
| --- | --- |
| `install.sh` | Linux/macOS installer / uninstall |
| `scripts/*.sh` | Linux/macOS user-facing commands |
| `scripts/lib/` | Shared Bash libraries (logging, Steam, GitHub, backups) |
| `scripts/windows/*.ps1` | Windows PowerShell counterparts |
| `scripts/millennium-mcp.py` | MCP server for AI assistants |
| `man/` | Manual pages (`millennium-*.1`) for every user-facing command |
| `Formula/` | Homebrew formula (`millennium-helpers.rb`) |
| `completions/` | Bash / Zsh / Fish / Nushell / PowerShell completions |
| `tests/` | Unit + behavioral suites (`tests/run_tests.sh`) |
| `tests/windows/` | Pester tests for PowerShell scripts (`make test-windows`) |

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
make lint              # shellcheck + ruff (+ version/man/completions gates)
make check-all         # lint + test
make test-windows      # Pester under tests/windows/ (requires pwsh)
make test-all-distros  # local + Debian/Ubuntu/Fedora via Docker (requires Docker)
```

## Versioning

`VERSION` at the repo root is the helpers package version (aligned with Scoop, Winget, Homebrew, and Nix). Bump it when cutting a release; installers copy it next to the shared libraries so `--version` / `-Version` work after install. Prefer git tags `vX.Y.Z` for releases.

**Cutting a release:** follow [docs/release_runbook.md](docs/release_runbook.md) end-to-end (local `make lint` / `make test` / `make test-windows`, version bump, CI green, then tag). Do not tag until ShellCheck and the test suite pass locally and on `main`.

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
make check-version   # VERSION ↔ Scoop / Winget / Homebrew
make check-man       # every command has a man page
make check-winget    # Winget manifest structure (docs-only; no winget validate)
```

Optional local hooks (see `.pre-commit-config.yaml`):

```bash
pip install pre-commit   # if needed
pre-commit install
pre-commit install --hook-type pre-push
```

**pre-commit** runs: remote [pre-commit-hooks](https://github.com/pre-commit/pre-commit-hooks) sanity checks (private keys, merge conflicts, large files, symlinks, trailing whitespace, EOF newlines, LF line endings), plus local shellcheck, ruff check + format `--check`, VERSION presence, packaging version sync, winget manifests, completions tests (when `completions/` changes), man-page coverage, actionlint (workflows; skipped if not installed), gitleaks on staged changes (skipped if not installed), and **PKGBUILD `pkgver` sync on every commit**.

**pre-push** runs: `make lint`, and `make test-windows` when the push range touches `scripts/windows/`, `tests/windows/`, or `completions/powershell/` (skipped if `pwsh` is missing).

When `sync-pkgver` updates `packaging/millennium-helpers-git/PKGBUILD` / `.SRCINFO`, the commit is aborted once so you can re-stage those files and retry (normal pre-commit autofix flow). Committed `pkgver` matches **HEAD at hook time** (the parent of the new commit)—a commit cannot embed its own short SHA. `pkgver()` in the PKGBUILD still recalculates from the tip at `makepkg` time.

## Style

- Bash: `set -euo pipefail`; source `common.sh` / `scripts/lib/*` rather than duplicating helpers.
- macOS ships Bash 3.2: under `set -u`, empty `"${arr[@]}"` / `"${arr[*]}"` is unbound. Prefer `${arr[@]+"${arr[@]}"}` (or a length guard) when an array may be empty. Avoid `"${arr[@]:-}"` (it iterates once with an empty value).
- Honor `NO_COLOR` (and `FORCE_COLOR` when forcing color).
- PowerShell: `Set-StrictMode -Version Latest`; gate debug noise behind `MILLENNIUM_DEBUG` or `-Verbose`.
- Do not commit packaging build artifacts (`packaging/*.pkg.tar.zst`, etc.).
- Keep Arch `-git` `pkgver` / `.SRCINFO` current with `make sync-pkgver` (no full rebuild needed). With `pre-commit install`, this runs automatically on every commit.

## Packaging notes

- Homebrew / Scoop (release) / Winget / Nix `millennium-helpers` consume the **trimmed GitHub Release assets**, not the auto-generated source archives.
- Homebrew Formula version is taken from the `releases/download/vX.Y.Z/…` URL. Do **not** add a redundant `version "X.Y.Z"` line — `brew audit` rejects it. Keep `license "MIT"`.
- Scoop is the supported multi-command Windows install path (`millennium`, `millennium-mcp`, and the individual commands).
- Scoop `millennium-helpers-git` is a nightly tip-of-`main` install (GitHub archive); it is outside the versioned release bump.
- Nix `packages.millennium-helpers` uses the Linux release tarball (`nix/release-info.nix`); `packages.millennium-helpers-git` builds from the flake source (commit in the version string). Default package is the release build.
- Winget manifests track the Windows zip URL/hash for documentation only. WinGet portable nested files allow `.exe` only, so these PowerShell scripts cannot pass `winget validate` as a multi-command portable package.
- `scripts/ci/update-packaging-versions.sh` updates Formula / Scoop release / Winget / versioned Arch / Nix release-info from a release tag + asset hashes.
- Versioned Arch (`packaging/millennium-helpers`) is bumped with Formula / Scoop / Winget on release (Linux tarball URL + sha256). Arch `-git` stays tip-of-main and is outside that bump.
- Man-page CI (`scripts/ci/check-man-pages.sh`) fails on mandoc `ERROR`/`FATAL` only; `WARNING`/`STYLE` are printed as notes.

## Pull requests

- Keep PRs focused; include a short summary and test plan.
- Mention any completion, man-page, or docs updates.
- CI must pass (multi-distro + macOS test matrix, ShellCheck, Ruff, man pages, Homebrew audit, completions, packaging checks).
