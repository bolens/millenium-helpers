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

Rough size: ~11 Bash lib modules, ~10 PowerShell lib modules (schedule/theme/purge/diag/repair/dispatcher
feature libs peeled; upgrade/shared remain); Go owns PATH `millennium`, MCP stdio (~Python escape hatch), 8 man pages, 12
completion files. CLI surface is gated by
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

- Dual help / completions / man / MCP schema maintained by hand (command suites until Endgame C)
- MCP argv mapping onto platform CLIs; Python hatch until Parallel retirement
- Upgrade dual libs kept for `NeedsLegacy` install handoff (Parallel)

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
| Dispatcher `millennium <cmd>` + suggestions | Y | Y | **Graduated/peeled** (Phase 6a + Endgame B) | Go `main_test` + `go.yml` dual-OS | Go `main_test` + `go.yml` | Shell/PS entrypoints + dispatcher dual libs removed |
| `version` / `-V` / root help | Y | Y | **Graduated** (Phase 6a) | Go + `go.yml` dual-OS | Go + `go.yml` | No dual libs to delete for meta |
| `diag` (health report) | Y | Y | **Graduated** (6w smoke + 6z peel) | `test_diag` + Go thin-wrap | Go thin-wrap | Dual libs removed |
| `diag doctor` / `--fix` | Y | Y | **Graduated** (6x dry-run + Endgame C live healthy) | `test_diag` + Go | Go thin-wrap | Completions/package cleanup still advisory |
| `diag --json` / `--share` / `--follow` | Y | Y | **Graduated** (6w JSON; Endgame C share/follow) | Go | Go | Redact + paste stub; capped follow |
| `diag logs` | Y | Y | **Graduated** (6y) | Go + thin-wrap | Go | No-logs path OK |
| `upgrade` download/verify/install | Y | Y | **Graduated** when writable (Endgame C); Linux non-root → `sudo` hint Graduated | `test_upgrade` + Go | Go thin-wrap | Dual libs for `MILLENNIUM_LEGACY=1` install handoff |
| `upgrade --rollback` apply | Y | Y | **Graduated** when writable (6u); list Graduated 6q | `test_upgrade` + Go | Go | Sudo handoff when unwritable |
| `upgrade --file` / `--sha256` | Y | Y | **Graduated** verify (6t) + dry-run (6s) | Y + Go | Y | Fail-closed SHA before install |
| `repair` | Y | Y | **Graduated/peeled** (6ab–6ad) | `test_repair` + Go thin-wrap | Go thin-wrap | Dual libs removed |
| `purge` | Y | Y | **Graduated/peeled** (6p smoke + 6r peel) | `test_purge` + Go thin-wrap | Go thin-wrap | Dual libs removed |
| `upgrade --all-users` | Y | — | Linux/macOS only | P | — | Keep contract-marked |
| `schedule` (all commands) | Y | Y* | **Graduated/peeled** (6c–6o) | Go + thin-wrap | Go + thin-wrap | *hooks Unix-only |
| `schedule --cron` | Y | — | Linux/macOS only | Y | — | Contract OS-only |
| `theme` list/install/update/remove | Y | Y | **Graduated** (Phase 6g peel) | `TestNativeTheme*` + `go.yml`; Bash/Pester via thin-wrap | Go + `go.yml` | Dual libs removed |
| `theme list --json` | Y | Y | **Graduated** (Phase 6g peel) | Go + `go.yml` dual-OS; Bash/Pester via thin-wrap | Go + `go.yml` | Long-name theme thin-wrap |
| `upgrade --rollback list` | Y | Y | **Graduated** (Phase 6q) | `TestNativeUpgradeRollbackList` + dual-OS `go.yml` | Go + `go.yml` | Dual libs retained for install handoff |
| `mcp` tools surface | Y | Y | **Graduated** (6aa `initialize` smoke); Python hatch retained | `test_mcp` | `millennium` / `millennium-mcp` | Hatch until explicit retirement |
| Install / uninstall helpers | Y | Y | **Go required** PATH `millennium` / `.exe` (Endgame A–B) | `test_install` | `install` | No shell/PS PATH dispatcher; uninstall clears both systemd scopes |
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
