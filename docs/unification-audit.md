# Unification audit (Bash / PowerShell → Go)

Inventory of the helper surface and a **parity matrix** for the single Go
runtime. Maintainer guide — see also [unification-roadmap.md](unification-roadmap.md).

Project: [README](../README.md). Index: [README.md](README.md).

---

## Scope today

| Surface | Path | Language |
| --- | --- | --- |
| PATH CLI | `bin/millennium` (`go/cmd/millennium`) | Go |
| Long-name helpers | Not installed on PATH; leftover twins via `commandFromArgv0` | Go |
| Shared libs | Go (`go/internal/*`); CI helpers in [`scripts/ci/`](../scripts/ci/) | Bash/PS install libs removed |
| Steam | `go/internal/steam` | Go (Unix + Windows) |
| CLI logging | `go/internal/logging` | Go |
| Zip extract | `go/internal/archive` | Go (theme + helpers install) |
| Install / uninstall | `go/internal/install` + Unix `install.sh`; Windows via packaging / `millennium.exe` | Go (+ Unix bootstrap) |
| MCP | `millennium mcp` | Go |
| Completions | [`completions/`](../completions/) | Bash / Zsh / Fish / Nushell / PowerShell |
| Man pages | [`man/`](../man/) | mandoc |
| Packaging | Formula, Nix, Arch, Scoop/Winget, deb/rpm/Chocolatey | various |

Go owns the product CLI (schedule, theme, diag, upgrade, purge, repair, mcp,
install/uninstall), Steam lifecycle, logging, safe zip extract, GitHub/API and
config paths, and MCP stdio. Surface is gated by
[`spec/cli-contract.yaml`](../spec/cli-contract.yaml)
([CONTRIBUTING](../CONTRIBUTING.md#linux--windows-parity)).

---

## Logic buckets

### Shared (portable — Go packages)

- `config.json` keys: `update_channel`, `github_token`, `backup_limit`, `backup_max_age_days`
- Helpers **track** (`release` / `main` / `tag` / `checkout`) vs client **channel** (`stable` / `beta` / `main`)
- GitHub release download + SHA256 verify; local `--file` / `--sha256`
- Backup rotate / rollback list
- Dispatcher command set + typo suggestion
- Theme list / install / update / remove semantics
- Helpers install track resolve, meta, archive fetch/extract

### OS-shaped (same intent, different mechanism)

- Steam find / close / relaunch
- Schedule: systemd (system + user) / launchd / cron / Task Scheduler
- Install roots (`/usr/local/lib/...` vs `%USERPROFILE%\.millennium-helpers`)
- Elevation (`sudo` / UAC); Linux sudoers drop-in from install
- Windows User PATH + PowerShell completion profile hooks

### Façade-only

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
| Flag casing | windows | Documented Pascal aliases in contract / completions |

---

## Parity matrix

Legend: **Y** = present · **P** = partial · **—** = N/A (contract OS-only) ·
Tests: Go unit under `go/` · smokes in [`.github/workflows/go.yml`](../.github/workflows/go.yml)
(Linux / Windows / macOS). Install suites under `tests/` + `test-suite.yml`.

| Capability | Linux | Windows | Go | Go tests / go.yml | Notes |
| --- | --- | --- | --- | --- | --- |
| Dispatcher `millennium <cmd>` + suggestions | Y | Y | Native | `main_test` + `go.yml` | Shell/PS PATH dispatchers removed |
| `version` / `-V` / root help | Y | Y | Native | Go + `go.yml` | |
| `diag` report / `--json` / `--share` / logs / `--follow` / doctor | Y | Y | Native | Go + dual-OS smokes | Live doctor under `DIAG_TEST_BYPASS_CHECKS` |
| `upgrade` download/verify/install/rollback | Y | Y | Native (+ Linux sudo handoff) | Go + dual-OS smokes | `--file` without checksum fails closed |
| `upgrade --all-users` | Y | — | Linux/macOS only | P | Contract-marked |
| `repair` | Y | Y | Native | Go + dual-OS smokes | |
| `purge` | Y | Y | Native | refuse/`--yes` unit + smokes | Dry-run smoked in `go.yml` |
| `schedule` (all commands) | Y | Y* | Native | cron/wizard/Steam seams in Go + `go.yml` | *hooks Unix-only |
| `schedule --cron` | Y | — | Linux/macOS only | Y (Unix smoke) | Contract OS-only |
| `theme` list/install/update/remove | Y | Y | Native | Go `theme`/`archive` + smokes | Zip-slip in Go `archive` |
| `mcp` tools surface | Y | Y | Native | Go MCP package + tools smokes | |
| Install / uninstall helpers | Y | Y | Native | Go `internal/install` fixtures (+ PATH/hook/sudoers); `test_install` / Pester = bootstrap help only | Network/SHA, wizard; Windows entry via packaging / `millennium.exe` |

---

## Open gaps (non-contract)

1. Marked completion lists sync from the contract (`make sync-cli-facade`); man
   OPTIONS / MCP schemas / nested flag bodies are still mostly hand-maintained
   (checked by `make check-cli-contract`).
2. User-facing docs may still show long-name examples (`millennium-repair`) in places;
   packaging/sudoers/completions use `millennium <cmd>` only.

---

## Related

- [Docs index](README.md) · [Unification roadmap](unification-roadmap.md) · [CLI contract](../spec/cli-contract.yaml)
- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [MCP](mcp.md) · [Release runbook](release_runbook.md)
