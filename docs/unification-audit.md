# Unification audit (Bash / PowerShell → Go)

Inventory of the helper surface and a **parity matrix** for the single Go
runtime. Maintainer guide — see also [unification-roadmap.md](unification-roadmap.md).

Project: [README](../README.md). Index: [README.md](README.md).

---

## Scope today

| Surface | Path | Language |
| --- | --- | --- |
| PATH CLI | `bin/millennium` (`go/cmd/millennium`) | Go |
| Long-name helpers | [`scripts/millennium-*.sh`](../scripts/), [`scripts/windows/*.ps1`](../scripts/windows/) | Thin-wrap → Go |
| Shared libs | [`scripts/lib/`](../scripts/lib/), [`scripts/windows/lib/`](../scripts/windows/lib/) | Bash / PowerShell (install-only); Steam, CLI logging, zip extract, GitHub API in Go |
| Steam | `go/internal/steam` | Go (Unix + Windows) |
| CLI logging | `go/internal/logging` | Go |
| Zip extract | `go/internal/archive` | Go (theme + Windows upgrade install) |
| MCP | `millennium mcp` / PATH `millennium-mcp` | Go |
| Completions | [`completions/`](../completions/) | Bash / Zsh / Fish / Nushell / PowerShell |
| Man pages | [`man/`](../man/) | mandoc |
| Packaging | Formula, Nix, Arch, Scoop/Winget, deb/rpm/Chocolatey | various |

Rough size: ~5 Bash + ~6 PowerShell install-oriented shared lib modules; Go owns
PATH `millennium`, Steam, CLI logging, safe zip extract, GitHub/API config paths,
MCP stdio, man pages, and completions wiring. CLI surface is gated by
[`spec/cli-contract.yaml`](../spec/cli-contract.yaml)
([CONTRIBUTING](../CONTRIBUTING.md#linux--windows-parity)).

---

## Logic buckets

### Shared (portable — Go packages)

- `config.json` keys: `update_channel`, `github_token`, `backup_limit`, `backup_max_age_days`
- Helpers **track** (`release` / `main` / `tag`) vs client **channel** (`stable` / `beta` / `main`)
- GitHub release download + SHA256 verify; local `--file` / `--sha256`
- Backup rotate / rollback list
- Dispatcher command set + typo suggestion
- Theme list / install / update / remove semantics

### OS-shaped (same intent, different mechanism)

- Steam find / close / relaunch
- Schedule: systemd (system + user) / launchd / cron / Task Scheduler
- Install roots (`/usr/lib` vs Steam `millennium\`)
- Elevation (`sudo` / UAC)

### Façade-only

- Dual help / completions / man / MCP schema maintained by hand (thin long-name wrappers remain)
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
| Flag casing | windows | Pascal aliases on PowerShell thin-wraps |

---

## Parity matrix

Legend: **Y** = present · **P** = partial · **—** = N/A (contract OS-only) ·
Tests: Bash behavioral/unit under `tests/` · Pester under `tests/windows/`.

| Capability | Linux | Windows | Go | Bash tests | Pester | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Dispatcher `millennium <cmd>` + suggestions | Y | Y | Native | `main_test` + `go.yml` | `go.yml` | Shell/PS PATH dispatchers removed |
| `version` / `-V` / root help | Y | Y | Native | Go + `go.yml` | Go + `go.yml` | |
| `diag` report / `--json` / `--share` / logs / `--follow` / doctor | Y | Y | Native | thin-wrap help | thin-wrap help | Dual-OS smokes in `go.yml`; live doctor under `DIAG_TEST_BYPASS_CHECKS` |
| `upgrade` download/verify/install/rollback | Y | Y | Native (+ Linux sudo handoff) | thin-wrap help | thin-wrap help | Dual-OS smokes in `go.yml` |
| `upgrade --all-users` | Y | — | Linux/macOS only | P | — | Contract-marked |
| `repair` | Y | Y | Native | thin-wrap help | thin-wrap help | Dual-OS smokes in `go.yml` |
| `purge` | Y | Y | Native | unique refuse/`--yes` seams | unique seams | Dry-run smoked in `go.yml` |
| `schedule` (all commands) | Y | Y* | Native | unique cron/wizard/Steam seams | thin-wrap help | *hooks Unix-only |
| `schedule --cron` | Y | — | Linux/macOS only | Y | — | Contract OS-only |
| `theme` list/install/update/remove | Y | Y | Native | canaries; zip-slip in Go `archive` | thin-wrap help | Dual-OS smokes in `go.yml` |
| `mcp` tools surface | Y | Y | Native | `test_mcp` | Go wrap | Dual-OS `initialize` smoke |
| Install / uninstall helpers | Y | Y | Requires Go PATH binary | `test_install` | `install` | Uninstall clears both systemd scopes |

---

## Open gaps (non-contract)

1. Timers / sudoers may still name long-name helpers (`millennium-upgrade`); migrate to `millennium upgrade` with installers.
2. Completions/man/MCP schema still hand-synced with the contract (CI gates help).

---

## Related

- [Docs index](README.md) · [Unification roadmap](unification-roadmap.md) · [CLI contract](../spec/cli-contract.yaml)
- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [MCP](mcp.md) · [Release runbook](release_runbook.md)
