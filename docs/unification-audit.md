# Unification audit (Bash / PowerShell → Go)

Inventory of the dual-shell Millennium Helpers surface and a **parity matrix**
for the migration to a single Go runtime. Maintainer guide — see also
[unification-roadmap.md](unification-roadmap.md).

Project: [README](../README.md). Index: [README.md](README.md).

---

## Scope today

| Surface | Path | Language |
| --- | --- | --- |
| Linux/macOS CLI | [`scripts/*.sh`](../scripts/) + [`scripts/lib/`](../scripts/lib/) | Bash |
| Windows CLI | [`scripts/windows/*.ps1`](../scripts/windows/) + [`lib/`](../scripts/windows/lib/) | PowerShell |
| MCP | Go `millennium mcp` / PATH `millennium-mcp`; Python escape hatch | Go (+ optional Python 3) |
| Completions | [`completions/`](../completions/) | Bash / Zsh / Fish / Nushell / PowerShell |
| Man pages | [`man/`](../man/) | mandoc |
| Packaging | Formula, Nix, Arch, Scoop/Winget, deb/rpm/Chocolatey | various |

Rough size: ~30 Bash lib modules, ~30 PowerShell lib modules, ~725 LOC MCP,
8 man pages, 12 completion files. CLI surface is gated by
[`spec/cli-contract.yaml`](../spec/cli-contract.yaml); remaining dual-shell
parity gaps are tracked in the matrix below
([CONTRIBUTING](../CONTRIBUTING.md#linux--windows-parity)).

---

## Logic buckets

### Shared (portable — first Go packages)

- `config.json` keys: `update_channel`, `github_token`, `backup_limit`, `backup_max_age_days`
- Helpers **track** (`release` / `main` / `tag`) vs client **channel** (`stable` / `beta` / `main`)
- GitHub release download + SHA256 verify; local `--file` / `--sha256`
- Backup rotate / rollback list
- Dispatcher command set + typo suggestion
- Theme list / install / update / remove semantics
- Version reporting from `VERSION`
- Global conventions: `--help` exit 0, unknown flags non-zero, `--dry-run` / `--yes` / `--quiet`

### Linux-shaped

- `/etc/sudoers.d/` drop-in; systemd timers (**prefer system**, fallback `systemd --user`); crontab (`--cron`)
- Flatpak / Steam Deck path overrides ([steam_deck.md](steam_deck.md))
- `--all-users` bootstrap linking (upgrade)
- Man / shell completion install paths (`install.sh`)

### Windows-shaped

- UAC / `RunAs`; Task Scheduler
- `.cmd` wrappers under `~/.millennium-helpers/bin`
- `%LOCALAPPDATA%\millennium-helpers` config root
- PascalCase flag aliases (`-Share`, `-DryRun`, …)

### Façade-only (should collapse)

- Duplicated suggestion algorithms:
  [`dispatcher.sh`](../scripts/lib/dispatcher.sh) /
  [`Dispatcher.ps1`](../scripts/windows/lib/Dispatcher.ps1)
- Dual help / completions / man / MCP schema maintained by hand
- MCP argv mapping onto platform CLIs

---

## Contract-only OS knobs

Not unpaid feature debt — kept in [`spec/cli-contract.yaml`](../spec/cli-contract.yaml):

| Knob | Platforms | Notes |
| --- | --- | --- |
| `schedule --cron` | linux, darwin | Force crontab vs systemd |
| `schedule --system` / `--user` | linux | Force systemd scope; default auto prefers system |
| `upgrade --all-users` | linux, darwin | Multi-UID Steam tree hooks |
| MCP `cron` | linux (documented) | Same as schedule `--cron` |
| Flag casing | windows legacy | Pascal aliases until PowerShell paths graduate |

---

## Parity matrix

Legend: **Y** = present · **P** = partial · **—** = N/A (contract OS-only) ·
Tests: Bash behavioral/unit under `tests/` · Pester under `tests/windows/`.

| Capability | Linux | Windows | Go end-state | Bash tests | Pester | Gap |
| --- | --- | --- | --- | --- | --- | --- |
| Dispatcher `millennium <cmd>` + suggestions | Y | Y | **Graduated** (Phase 6a) | Go `main_test` + `go.yml` dual-OS | Go `main_test` + `go.yml` | Bash/Pester dispatcher suites remain until peel-off |
| `version` / `-V` / root help | Y | Y | **Graduated** (Phase 6a) | Go + `go.yml` dual-OS | Go + `go.yml` | No dual libs to delete for meta |
| `diag` (health report) | Y | Y | **Native report** | `test_diag` + Go | `millennium-diag` + Go | — |
| `diag doctor` / `--fix` | Y | Y | **Dry-run + live native** | `test_diag` + Go | `millennium-diag` | Completions/package cleanup still advisory |
| `diag --json` / `--share` / `--follow` | Y | Y | **Native** (json/share/follow) | Go | Go | Redact + paste.rs; filter-tail |
| `upgrade` download/verify/install | Y | Y | **Native when writable**; Linux non-root → `sudo` re-exec | `test_upgrade` + Go | `millennium-upgrade` | Custom unwritable `MILLENNIUM_LIB_DIR` fails clearly (no sudo) |
| `upgrade --rollback` / `list` | Y | Y | **list + apply native when writable**; else Linux `sudo` | `test_upgrade` + Go | `millennium-upgrade` | — |
| `upgrade --file` / `--sha256` | Y | Y | **Verify native**; install legacy | Y + Go | Y | Fail-closed SHA before legacy |
| `repair` | Y | Y | **Dry-run + live user-path native** | `test_repair` + Go | `millennium-repair` + Go | Hook reinstall still legacy as needed |
| `purge` (+ `--yes` / dry-run) | Y | Y | **Dry-run + live Unix/Windows native** | `test_purge` + Go | `millennium-purge` | — |
| `upgrade --all-users` | Y | — | Linux/macOS only | P | — | Keep contract-marked |
| `schedule enable/disable/status` | Y | Y | **Graduated/peeled** (status 6i; enable/disable 6k) | `TestNativeSchedule*` + `go.yml`; Bash/Pester via thin-wrap | Go + `go.yml` | Enable dual libs removed |
| `schedule pre/post-update` | Y | — | **Graduated/peeled** (Phase 6o); Unix/macOS; Windows N/A | `TestNativeScheduleHooksGate` + Linux `go.yml`; Bash thin-wrap | — | Hooks dual lib removed |
| `schedule setup` wizard | Y | Y | **Graduated/peeled** (Phase 6n) | `TestNativeScheduleSetupWizard` + dual-OS `go.yml`; Bash/Pester thin-wrap | Go + `go.yml` | Wizard dual libs removed |
| `schedule config get/set/list` | Y | Y | **Graduated** (Phase 6c peel) | Go `TestNativeConfig` + `go.yml` dual-OS; Bash/Pester via thin-wrap | Go + `go.yml` | Dual libs removed; long-name `config` execs Go |
| `schedule --cron` | Y | — | Linux/macOS only | Y | — | Contract OS-only |
| `theme` list/install/update/remove | Y | Y | **Graduated** (Phase 6g peel) | `TestNativeTheme*` + `go.yml`; Bash/Pester via thin-wrap | Go + `go.yml` | Dual libs removed; long-name theme execs Go |
| `theme list --json` | Y | Y | **Graduated** (Phase 6g peel) | Go + `go.yml` dual-OS; Bash/Pester via thin-wrap | Go + `go.yml` | Long-name theme thin-wrap |
| `purge --dry-run` | Y | Y | **Graduated** (Phase 6p) | `TestNativePurgeDryRun` + dual-OS `go.yml` | Go + `go.yml` | Dual libs until peel |
| `upgrade --rollback list` | Y | Y | **Graduated** (Phase 6q) | `TestNativeUpgradeRollbackList` + dual-OS `go.yml` | Go + `go.yml` | Dual libs until peel |
| `mcp` tools surface | Y | Y | **Done:** Go owns stdio + `--register`; PATH twin; Python opt-in escape | `test_mcp` (`MCP_IMPL`) | `millennium` / `millennium-mcp` | Python suite retained until graduation |
| Install / uninstall helpers | Y | Y | **Go-first** PATH `millennium` / `.exe`; versioned OS/arch release archives | `test_install` | `install` | Long-name helpers + shell/PS fallback remain; uninstall clears both systemd scopes |
| Install track / doctor sync | Y | Y | Native | `test_install_track` | `InstallTrack` | Shared meta JSON |
| Completions | Y | Y | Generated from contract | `test_completions` | `completions` | Codegen later |
| Man pages | Y | — | Generated / kept | `check-man` | — | Keep shipping on Unix |

**Graduation:** a row turns fully green only when Go implements the capability per
contract **and** dual-OS automated tests pass. See
[unification-roadmap.md](unification-roadmap.md#command-graduation-rule).

---

## Related

- [Docs index](README.md) · [Unification roadmap](unification-roadmap.md) · [CLI contract](../spec/cli-contract.yaml)
- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [MCP](mcp.md) · [Release runbook](release_runbook.md)
