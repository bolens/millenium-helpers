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
| MCP | [`scripts/millennium-mcp.py`](../scripts/millennium-mcp.py) | Python 3 |
| Completions | [`completions/`](../completions/) | Bash / Zsh / Fish / Nushell / PowerShell |
| Man pages | [`man/`](../man/) | mandoc |
| Packaging | Formula, Nix, Arch, Scoop, Winget | various |

Rough size: ~30 Bash lib modules, ~30 PowerShell lib modules, ~725 LOC MCP,
8 man pages, 12 completion files. No shared IDL — parity is manual
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
| Dispatcher `millennium <cmd>` + suggestions | Y | Y | Native (Phase 1) | `test_millennium_dispatcher`, `test_dispatcher` | `millennium`, `Dispatcher` | Port suggest + dispatch |
| `version` / `-V` | Y | Y | Native (Phase 1) | various | various | Go embed/`VERSION` |
| `diag` (health report) | Y | Y | **Native report** | `test_diag` + Go | `millennium-diag` + Go | — |
| `diag doctor` / `--fix` | Y | Y | **Dry-run + live native** | `test_diag` + Go | `millennium-diag` | Completions/package cleanup still advisory |
| `diag --json` / `--share` / `--follow` | Y | Y | **Native** (json/share/follow) | Go | Go | Redact + paste.rs; filter-tail |
| `upgrade` download/verify/install | Y | Y | **Native when writable**; Linux non-root → `sudo` re-exec | `test_upgrade` + Go | `millennium-upgrade` | Custom unwritable `MILLENNIUM_LIB_DIR` fails clearly (no sudo) |
| `upgrade --rollback` / `list` | Y | Y | **list + apply native when writable**; else Linux `sudo` | `test_upgrade` + Go | `millennium-upgrade` | — |
| `upgrade --file` / `--sha256` | Y | Y | **Verify native**; install legacy | Y + Go | Y | Fail-closed SHA before legacy |
| `repair` | Y | Y | **Dry-run + live user-path native** | `test_repair` + Go | `millennium-repair` + Go | Hook reinstall still legacy as needed |
| `purge` (+ `--yes` / dry-run) | Y | Y | **Dry-run + live Unix/Windows native** | `test_purge` + Go | `millennium-purge` | — |
| `upgrade --all-users` | Y | — | Linux/macOS only | P | — | Keep contract-marked |
| `schedule enable/disable/status` | Y | Y | **Native**; Linux systemd prefers **system**, else user | `test_schedule` + Go | `millennium-schedule` | setup still legacy; Bash path user-only |
| `schedule pre/post-update` | Y | — | **Native** (Unix/macOS; Windows N/A) | `test_schedule` + Go | — | Scheduler gate + Steam/diag |
| `schedule setup` wizard | Y | Y | Legacy (Phase 4+) | Y | Y | Interactive both OSes |
| `schedule config get/set/list` | Y | Y | **Native Go (Phase 2)** | Y + Go | Y + Go | Config path graduated |
| `schedule --cron` | Y | — | Linux/macOS only | Y | — | Contract OS-only |
| `theme` list/install/update/remove | Y | Y | **Native Go (list + mutate)** | `test_theme` + Go | `millennium-theme` + Go | zip-slip safe extract; `--yes` on remove |
| `theme --json` | Y | Y | **Native (Phase 2 list)** | Y + Go | Y + Go | — |
| `mcp` tools surface | Y | Y | Phase 5 → Go CLI | `test_mcp` | `millennium-mcp` | Stop dual argv maps |
| Install / uninstall helpers | Y | Y | Native (Phase 4) | `test_install` | `install` | Replace curl/irm payloads |
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
