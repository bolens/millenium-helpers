# Unification notes (Bash / PowerShell → Go)

Millennium Helpers ships a **single Go CLI** (`bin/millennium`). Feature
Bash/PowerShell scripts and install-time shared libs are gone. New installs put
only `millennium` on PATH; leftover long-name argv0 twins still dispatch if
present. Unix `install.sh` bootstraps into `millennium install`; Windows uses
Scoop/Winget/Chocolatey or a standalone `millennium.exe`.

Parity on Linux, macOS, and Windows is enforced by Go unit tests and
[`.github/workflows/go.yml`](../.github/workflows/go.yml) smokes.

| Doc | Role |
| --- | --- |
| [unification-audit.md](unification-audit.md) | Inventory + parity matrix |
| [`spec/cli-contract.yaml`](../spec/cli-contract.yaml) | Machine-readable commands / flags |
| [CHANGELOG.md](../CHANGELOG.md) | Shipped notes |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Dev setup (`make build`, `make test-go`) |

---

## Status

| Milestone | State |
| --- | --- |
| Go owns schedule / theme / diag / upgrade / purge / repair / mcp | Done |
| Feature `scripts/millennium-*.sh` / `scripts/windows/millennium-*.ps1` removed | Done |
| Release + install stop shipping/copying feature scripts | Done |
| Feature CI = `go.yml` (ubuntu + windows + macos) | Done |
| `test-suite.yml` = install / packaging / completions (no feature-script suites) | Done |
| `millennium install` / `uninstall` (network, sudoers, Windows PATH/hooks, wizard) | Done |
| Windows `install.ps1` removed (Scoop/Winget/standalone `millennium.exe`) | Done |
| Install-time Bash/PS libs removed (`common.sh` / `common.ps1` / `scripts/*/lib`) | Done |
| PATH = `millennium` only (no new long-name twins) | Done |
| Contract-driven façade sync (completions / man / MCP) | Done |
| Flag-level façade sync (bash + PowerShell completion bodies) | Done |
| Long-name sudoers + completion symlink cleanup | Done |
| Install fixture tests in Go (`go test ./internal/install`) | Done |
| User docs use `millennium <cmd>` (not long-name PATH twins) | Done |

`make build` → `bin/millennium`. Release CD embeds per-OS/arch Go binaries and
waits on a green required-CI gate (`go.yml` + `test-suite.yml` + other packaging
checks). **Feature regressions must fail `go.yml`.**

---

## Current shape

| Area | Notes |
| --- | --- |
| PATH entry | `millennium` / `millennium.exe` only on new installs |
| Long-name helpers | Not installed; `commandFromArgv0` still maps leftover twins → subcommands |
| Completions | Register `millennium` only (nested `millennium <cmd>…`) |
| Sudoers | Allowlist `millennium upgrade|diag|repair|purge` (no PATH twins) |
| Steam lifecycle | Go (`go/internal/steam`); Windows + Unix |
| Shared logging | Go (`go/internal/logging`) |
| Zip extract | Go (`go/internal/archive`); theme + helpers install use it |
| GitHub / config | Go (`githubapi`, `config`) |
| MCP | `millennium mcp` (Go); leftovers may still invoke as `millennium-mcp` via argv0 |
| Installers | Go `millennium install` / `uninstall`; Unix thin `install.sh`; Windows packaging / standalone exe |
| Install meta / license | `VERSION`, `install-meta.json`, `MILLENNIUM-LICENSE.md` under lib/install root |
| CI helpers | [`scripts/ci/`](../scripts/ci/) (includes `release_assets.sh`) |
| Schedule timers | systemd / launchd / cron / Task Scheduler invoke `millennium <cmd>` |
| `MILLENNIUM_LEGACY=1` | Obsolete for Go-owned commands |

Local checks: `make test-go` (features + install fixtures) + `make test` /
`make test-windows` (bootstrap / packaging / shell completions). CI mirrors that
split.

---

## Remaining work

Unification feature peel is complete. Further optional polish (not blocking):

1. Generate man OPTIONS blocks and MCP `InputSchema` maps from the contract
   (completion lists + flag bodies already sync via `make sync-cli-facade`).

---

## When changing a command

1. Update [`spec/cli-contract.yaml`](../spec/cli-contract.yaml) first if flags/subcommands change
   (include `short:` for dispatcher commands used by zsh sync).
2. Run `make sync-cli-facade` to refresh marked completion lists / flag bodies.
3. Implement in Go under `go/`; keep `commandFromArgv0` working for leftover twins.
4. Cover with `make test-go` and the Linux / Windows / macOS jobs in [`go.yml`](../.github/workflows/go.yml).
5. Keep completions, man, and MCP schemas aligned (`make check-cli-contract`).
6. PATH installs only `millennium`; do not reintroduce long-name twins.
7. Note the change in [CHANGELOG.md](../CHANGELOG.md).

---

## Definition of done (surface)

A surface is “done” when:

1. Go implements it with parity to [`spec/cli-contract.yaml`](../spec/cli-contract.yaml).
2. Automated tests pass on **Linux, Windows, and macOS** in CI (`go.yml` unit and/or smokes).
3. MCP / completions / man (where applicable) describe the Go surface.
4. The [parity matrix](unification-audit.md#parity-matrix) row matches reality.

Install packaging stays green under `test-suite.yml`.

---

## Related

- [Docs index](README.md) · [Unification audit](unification-audit.md) · [CLI contract](../spec/cli-contract.yaml)
- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [Release runbook](release_runbook.md) · [MCP](mcp.md)
