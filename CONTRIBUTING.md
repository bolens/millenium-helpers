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
- **Dev Container**: open the repo in a container (installs Pester, PSScriptAnalyzer, and pre-commit hooks on create). Then run `make check-all`.
- **Nix**: `nix develop` for a shell with bash, python, shellcheck, and ruff.

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
| `completions/` | Bash / Zsh / Fish / Nushell completions |
| `tests/` | Unit + behavioral suites (`tests/run_tests.sh`) |
| `tests/windows/` | Pester tests for PowerShell scripts |

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

```bash
make test           # local suite
make lint           # shellcheck + ruff
make check-all      # lint + test
make test-all-distros  # local + Debian/Ubuntu/Fedora Docker runs (optional)
```

Windows: run the Pester suite under `tests/windows/` on a Windows host or CI.

## Versioning

`VERSION` at the repo root is the helpers package version (aligned with Scoop, Winget, and the Homebrew Formula). Bump it when cutting a release; installers copy it next to the shared libraries so `--version` / `-Version` work after install. Prefer git tags `vX.Y.Z` for releases.

Tagging `vX.Y.Z` runs the release workflow: it waits for the Test Suite on that commit, drafts a GitHub release with checksums, then opens a packaging PR that fills Formula/Scoop/Winget URLs and SHA256s from the tag source archives. Optional repo secret `PACKAGING_PAT` (classic PAT with `contents` + `pull-requests`) makes that packaging PR trigger CI automatically.

Local checks:
```bash
make check-version   # VERSION ↔ Scoop / Winget / Homebrew
make check-man       # every command has a man page
make check-winget    # Winget manifest structure
```

Optional local hooks: `pre-commit install` (see `.pre-commit-config.yaml`) runs shellcheck, ruff, VERSION presence, version sync, and man-page coverage.

## Style

- Bash: `set -euo pipefail`; source `common.sh` / `scripts/lib/*` rather than duplicating helpers.
- macOS ships Bash 3.2: under `set -u`, empty `"${arr[@]}"` / `"${arr[*]}"` is unbound. Prefer `${arr[@]+"${arr[@]}"}` (or a length guard) when an array may be empty. Avoid `"${arr[@]:-}"` (it iterates once with an empty value).
- Honor `NO_COLOR` (and `FORCE_COLOR` when forcing color).
- PowerShell: `Set-StrictMode -Version Latest`; gate debug noise behind `MILLENNIUM_DEBUG` or `-Verbose`.
- Do not commit packaging build artifacts (`packaging/*.pkg.tar.zst`, etc.).

## Packaging notes

- Homebrew Formula version is taken from the stable `url` tag (`…/vX.Y.Z.tar.gz`). Do **not** add a redundant `version "X.Y.Z"` line — `brew audit` rejects it. Keep `license "MIT"`.
- `scripts/ci/update-packaging-versions.sh` updates Formula URL/SHA256 (and strips any stray `version` line), Scoop, and Winget from a release tag.
- Man-page CI (`scripts/ci/check-man-pages.sh`) fails on mandoc `ERROR`/`FATAL` only; `WARNING`/`STYLE` are printed as notes.

## Pull requests

- Keep PRs focused; include a short summary and test plan.
- Mention any completion, man-page, or docs updates.
- CI must pass (multi-distro + macOS test matrix, ShellCheck, Ruff, man pages, Homebrew audit, completions, packaging checks).
