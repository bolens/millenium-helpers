# Unification roadmap (Bash / PowerShell → Go)

Phased plan to replace dual-shell maintenance with one **Go** CLI while
keeping **full feature and test parity** on Linux, macOS, and Windows.

Baseline inventory: [unification-audit.md](unification-audit.md).
Machine-readable CLI: [`spec/cli-contract.yaml`](../spec/cli-contract.yaml).
Project: [README](../README.md). Index: [README.md](README.md).

---

## Parity policy

- User-facing features match across supported OSes.
- OS-shaped *implementations* (systemd vs Task Scheduler, sudoers vs UAC) are
  adapters, not product forks.
- Silent gaps are forbidden. Contract-marked **OS-only** knobs (e.g.
  `schedule --cron`) are the only exceptions — see the audit.

---

## Command graduation rule

Do **not** remove or stop testing a legacy `.sh` / `.ps1` path for command *C*
until all of the following are true:

1. Go implements *C* with feature parity per [`spec/cli-contract.yaml`](../spec/cli-contract.yaml).
2. Automated tests for *C* run and pass on **both** Linux and Windows in CI
   (shared table-driven Go tests and/or dual-OS behavioral jobs).
3. MCP, completions, and man pages (where applicable) describe the Go surface.
4. The audit [parity matrix](unification-audit.md#parity-matrix) row for *C* is
   updated to green.

Keep Bash + Pester green for unmigrated commands. Supersede suites
**command-by-command** — do not rewrite everything in one PR.

### PR checklist (migrating a command)

- [ ] Contract updated first (if flags/subcommands change)
- [ ] Go implementation + dual-OS tests
- [ ] Legacy scripts still present until graduation (or still tested)
- [ ] Parity matrix row updated in [unification-audit.md](unification-audit.md)
- [ ] Completions / man / MCP updated if the user surface changed

---

## Phases

| Phase | Goal | Exit criteria |
| --- | --- | --- |
| **0 — Spec + gate** | CLI contract + CI drift check | `make check-cli-contract` in `make lint` |
| **1 — MVP strangler** | Go `millennium`: native `version` / `help` / suggestions; other cmds exec legacy | Linux + Windows build + smoke; PATH still works; matrix published |
| **2 — Config + read-mostly** | Native config get/set/list, `theme list`, read-only diag | Graduation rule for those paths |
| **3 — Mutating core** | Native upgrade / repair / purge / doctor | Graduation rule; optional `MILLENNIUM_LEGACY=1` fallback |
| **4 — Schedule + installers** | Native timers/tasks + Go install/uninstall | Feature-equal schedule + install smokes both OSes |
| **5 — MCP + cleanup** | MCP → Go CLI; delete dual libs | **Definition of done** below |

### Definition of done (Phase 5)

- Every contract feature implemented **once** in Go.
- Every parity-matrix row green.
- Bash / Pester suites retired only after the Go dual-OS suite supersedes them.
- CONTRIBUTING “Linux / Windows parity” checklist replaced by contract + Go CI.
- `make check-all` includes contract check, `go test ./...`, and dual-OS
  behavioral jobs against the Go binary.

---

## MVP + Phase 2 shipped in-tree

| Artifact | Role |
| --- | --- |
| [`spec/cli-contract.yaml`](../spec/cli-contract.yaml) | Source of truth for commands / flags / platforms |
| [`scripts/ci/check-cli-contract.py`](../scripts/ci/check-cli-contract.py) | Drift gate (MCP, man, completions) |
| [`go/`](../go/) | Go module: `cmd/millennium` strangler |
| `make build` / `make test-go` / `make check-cli-contract` | Local DX |

### Native vs legacy (current)

| Path | Implementation |
| --- | --- |
| `millennium version` / help / suggestions | Native |
| `millennium schedule config …` | Native (`internal/config`) |
| `millennium schedule status` | Native (`internal/schedule`) |
| `millennium schedule enable\|disable --dry-run` | Native |
| `millennium schedule enable\|disable` (Unix) | Native user systemd / launchd / cron |
| `millennium schedule enable\|disable` (Windows live) | Legacy (admin Task Scheduler) |
| `millennium schedule setup` / pre\|post-update | Legacy |
| `millennium theme list` [`--json`] | Native (`internal/theme`) |
| `millennium diag` (bare / quiet) | Native read-only summary (`internal/diag`) |
| `millennium diag doctor\|--fix\|--json\|--share\|…` | Legacy |
| `millennium upgrade --rollback list` | Native (`internal/upgrade`) |
| `millennium upgrade --file … --dry-run` (+ SHA verify) | Native verify / announce |
| `millennium upgrade` (remote) | Native GitHub resolve + download + SHA; legacy extract/install |
| `millennium upgrade --rollback <id>` | Legacy apply |
| `millennium purge --dry-run` | Native plan (`internal/purge`) |
| `millennium purge` (live, Unix) | Native (confirm / `--yes`); Windows → legacy |
| `millennium repair --dry-run` | Native plan (`internal/repair`) |
| `millennium repair` (live) | Native user-path chown/htmlcache (theme/hooks → legacy as needed) |
| Other theme mutate / mcp | Legacy |

Force legacy for a native path: `MILLENNIUM_LEGACY=1`.

Experimental: run the Go binary directly; installers still deploy shell
dispatchers by default.

---

## Test parity (end-state)

| Layer | Requirement |
| --- | --- |
| Contract / static | `check-cli-contract` aligns MCP, completions, man, Go registration |
| Unit | Table-driven Go tests; OS packages use tags/skips only for OS APIs |
| Behavioral | Help / dry-run / happy / failure per command on **linux** and **windows** CI |
| Packaging | Install smokes stay green for Go-first assets on both platforms |
| Coverage gate | Before deleting legacy tests for *C*, Go coverage for *C* must replace them |

---

## Related

- [Docs index](README.md) · [Unification audit](unification-audit.md) · [CLI contract](../spec/cli-contract.yaml)
- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [Release runbook](release_runbook.md) · [MCP](mcp.md)
