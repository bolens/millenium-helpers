# Unification notes (Bash / PowerShell → Go)

Millennium Helpers implements the CLI in **Go** (`bin/millennium`), with
long-name `millennium-*` scripts as thin wraps. Keep **full feature and test
parity** on Linux, macOS, and Windows.

| Doc | Role |
| --- | --- |
| [unification-audit.md](unification-audit.md) | Inventory + parity matrix |
| [`spec/cli-contract.yaml`](../spec/cli-contract.yaml) | Machine-readable commands / flags |
| [CHANGELOG.md](../CHANGELOG.md) | Shipped notes |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Dev setup (`make build`, `make test-go`) |

---

## Current shape

| Area | Notes |
| --- | --- |
| PATH entry | Go only (`millennium` / `millennium.exe`); no shell/PS PATH dispatcher |
| Long-name helpers | Thin-wrap to Go (no `common.sh` / `common.ps1` sourcing) |
| Steam lifecycle | Go (`go/internal/steam`); Windows + Unix |
| Shared logging | Go (`go/internal/logging`) for CLI; Bash `logging.sh` keeps install-only helpers (`execute`, `write_file`, …) |
| Zip extract | Go (`go/internal/archive`); theme wraps it |
| GitHub / config backup | Go (`githubapi`, `config`); dead Bash `github.sh` / `backup.sh` / `archive.sh` removed |
| MCP | `millennium mcp` / PATH `millennium-mcp` argv0 twin (Go) |
| Installers | `install.sh` / `install.ps1` require a built Go binary |
| `MILLENNIUM_LEGACY=1` | Obsolete for Go-owned commands (they stay native) |

`make build` → `bin/millennium`. Release CD embeds per-OS/arch Go binaries and
waits on a green required-CI gate before packaging assets.

CI (`go.yml`): dual-OS unit tests + smokes, plus Linux `go vet` / `gofmt`,
golangci-lint, and govulncheck.

---

## Remaining optional work

- Install-time Bash/PS libs still in tree: `logging.sh` / `version.sh` / `install_track.sh` / `release_assets.sh` / `millennium_license.sh`; Windows `Logging` / `Args` / `Version` / `Config` / `License` / `InstallTrack`
- Further trim long-name Bash/Pester suites where unique seams remain (schedule/theme/purge)
- Migrate systemd/Task Scheduler units and sudoers fully onto `millennium <cmd>` (drop long-name PATH dependence) — needs installer/consumers

---

## When changing a command

1. Update [`spec/cli-contract.yaml`](../spec/cli-contract.yaml) first if flags/subcommands change.
2. Implement in Go under `go/`; keep long-name thin-wraps forwarding argv.
3. Cover with `make test-go` and dual-OS jobs in [`.github/workflows/go.yml`](../.github/workflows/go.yml).
4. Keep completions, man, and MCP schemas aligned (`make check-cli-contract`).
5. Do not delete a long-name entrypoint until timers/sudoers/docs that still name it are migrated.
6. Note the change in [CHANGELOG.md](../CHANGELOG.md).

---

## Definition of done (surface)

A surface is “done” when:

1. Go implements it with parity to [`spec/cli-contract.yaml`](../spec/cli-contract.yaml).
2. Automated tests pass on **Linux and Windows** in CI (Go unit and/or `go.yml` smokes).
3. MCP / completions / man (where applicable) describe the Go surface.
4. The [parity matrix](unification-audit.md#parity-matrix) row matches reality.

Keep Bash + Pester green for long-name thin-wrap residuals and unique seams
(cron, zip-slip canaries, install packaging) that Go dual-OS smoke does not cover.

---

## Related

- [Docs index](README.md) · [Unification audit](unification-audit.md) · [CLI contract](../spec/cli-contract.yaml)
- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [Release runbook](release_runbook.md) · [MCP](mcp.md)
