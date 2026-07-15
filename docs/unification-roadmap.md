# Unification notes (Bash / PowerShell → Go)

Millennium Helpers ships a **single Go CLI** (`bin/millennium`). Installed
long-name PATH entries are argv0 twins of that binary. Feature Bash/PowerShell
scripts were peeled out; installers keep install-time libs only.

Parity on Linux, macOS, and Windows is enforced by Go unit tests and
[`.github/workflows/go.yml`](../.github/workflows/go.yml) smokes.

| Doc | Role |
| --- | --- |
| [unification-audit.md](unification-audit.md) | Inventory + parity matrix |
| [`spec/cli-contract.yaml`](../spec/cli-contract.yaml) | Machine-readable commands / flags |
| [CHANGELOG.md](../CHANGELOG.md) | Shipped notes |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Dev setup (`make build`, `make test-go`) |

---

## Status (post script peel)

| Milestone | State |
| --- | --- |
| Go owns schedule / theme / diag / upgrade / purge / repair / mcp | Done |
| PATH long-name argv0 twins (no shell/PS feature bodies) | Done |
| Feature `scripts/millennium-*.sh` / `scripts/windows/millennium-*.ps1` removed | Done |
| Release + install stop shipping/copying feature scripts | Done |
| Feature CI = `go.yml` (ubuntu + windows + macos) | Done |
| `test-suite.yml` = install / unit libs / packaging / completions | Done |

`make build` → `bin/millennium`. Release CD embeds per-OS/arch Go binaries and
waits on a green required-CI gate (`go.yml` + `test-suite.yml` + other packaging
checks). **Feature regressions must fail `go.yml`.**

---

## Current shape

| Area | Notes |
| --- | --- |
| PATH entry | Go only (`millennium` / `millennium.exe`); no shell/PS PATH dispatcher |
| Long-name helpers | PATH argv0 twins of Go (`commandFromArgv0`); no checkout feature-script fallbacks |
| Steam lifecycle | Go (`go/internal/steam`); Windows + Unix |
| Shared logging | Go (`go/internal/logging`) for CLI; Bash `logging.sh` keeps install-only helpers (`execute`, `write_file`, …) |
| Zip extract | Go (`go/internal/archive`); theme wraps it |
| GitHub / config backup | Go (`githubapi`, `config`) |
| MCP | `millennium mcp` / PATH `millennium-mcp` argv0 twin (Go) |
| Installers | `install.sh` / `install.ps1` require a built Go binary; install all long names as Go twins |
| Schedule timers | systemd / launchd / cron / Task Scheduler invoke `millennium <cmd>` (rewrite on next enable) |
| `MILLENNIUM_LEGACY=1` | Obsolete for Go-owned commands (they stay native) |

Local checks: `make test-go` (feature parity) + `make test` / `make test-windows`
(install-time only). CI mirrors that split.

---

## Remaining optional work

Ordered roughly by leverage; **none block shipping** the peeled feature surface.

1. **Install-time libs** — still Bash/PS: `logging.sh` / `version.sh` / `install_track.sh` / `release_assets.sh` / `millennium_license.sh`; Windows `Logging` / `Args` / `Version` / `Config` / `License` / `InstallTrack`. Keep until installers move.
2. **Port installers to Go** — replace `install.sh` / `install.ps1` (and eventually peel install libs). Large surface; own milestone.
3. **Long-name PATH twins** — still useful for timers/sudoers/docs; migrate docs/timers to `millennium <cmd>` first, then drop twin installs if desired.
4. **Contract-driven façade sync** — completions / man / MCP schema stay hand-aligned; CI already gates drift via `make check-cli-contract`.

---

## When changing a command

1. Update [`spec/cli-contract.yaml`](../spec/cli-contract.yaml) first if flags/subcommands change.
2. Implement in Go under `go/`; keep long-name PATH twins (`commandFromArgv0`) in sync while twins still ship.
3. Cover with `make test-go` and the Linux / Windows / macOS jobs in [`go.yml`](../.github/workflows/go.yml).
4. Keep completions, man, and MCP schemas aligned (`make check-cli-contract`).
5. Do not delete a long-name PATH twin until timers/sudoers/docs that still name it are migrated.
6. Note the change in [CHANGELOG.md](../CHANGELOG.md).

---

## Definition of done (surface)

A surface is “done” when:

1. Go implements it with parity to [`spec/cli-contract.yaml`](../spec/cli-contract.yaml).
2. Automated tests pass on **Linux, Windows, and macOS** in CI (`go.yml` unit and/or smokes).
3. MCP / completions / man (where applicable) describe the Go surface.
4. The [parity matrix](unification-audit.md#parity-matrix) row matches reality.

Install packaging and shared install libs stay green under `test-suite.yml`.

---

## Related

- [Docs index](README.md) · [Unification audit](unification-audit.md) · [CLI contract](../spec/cli-contract.yaml)
- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [Release runbook](release_runbook.md) · [MCP](mcp.md)
