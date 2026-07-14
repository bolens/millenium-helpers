# Unification roadmap (Bash / PowerShell → Go)

Replace dual-shell maintenance with one **Go** CLI while keeping **full feature
and test parity** on Linux, macOS, and Windows.

| Doc | Role |
| --- | --- |
| [unification-audit.md](unification-audit.md) | Inventory + detailed parity matrix |
| [`spec/cli-contract.yaml`](../spec/cli-contract.yaml) | Machine-readable commands / flags |
| [CHANGELOG.md](../CHANGELOG.md) | Shipped slice notes |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Dev setup (`make build`, `make test-go`) |

---

## Status at a glance

| Phase | Status | Notes |
| --- | --- | --- |
| **0 — Spec + gate** | Done | Contract + `make check-cli-contract` in lint |
| **1 — MVP strangler** | Done | `go/` Cobra dispatcher + legacy exec |
| **2 — Config + read-mostly** | Done | `schedule config`, `theme list`, bare diag |
| **3 — Mutating core** | Done | Upgrade/repair/purge/diag (incl. follow) native |
| **4 — Schedule + installers** | Done | Schedule + installers Go-first; legacy dual-scope systemd cleanup (4m) |
| **5 — MCP + cleanup** | Not started | MCP still Python; dual libs still required |

Force any native path back to shell/PS: `MILLENNIUM_LEGACY=1`.

`make build` → `bin/millennium`. Unix `install.sh` and Windows `install.ps1`
prefer that Go binary for PATH `millennium` / `millennium.exe` (shell/PS
fallback). Release CD embeds per-OS/arch Go binaries and versioned archives;
builds wait on a green required-CI gate before packaging assets.

---

## How to read progress

| Mark | Meaning |
| --- | --- |
| Done | Native Go path for this surface (may still fall back to legacy on some OS/euid cases) |
| Partial | Native for dry-run / some OS / some flags; live or other OS still legacy |
| Legacy | Still Bash / PowerShell / Python |
| Blocked | Waiting on another slice (elevation, packaging, or dual-OS CI) |

**Graduation** (delete legacy for command *C*) is stricter than “native exists” —
see [Command graduation rule](#command-graduation-rule). Rows marked Done here
are strangler progress, not automatic permission to delete `.sh` / `.ps1`.

---

## Next up (recommended order)

Work through this queue; check items off as PRs land and update this list.

1. [x] **Windows + packaging Go-first** — `install.ps1` prefers `.exe`; versioned OS/arch release assets; from-source / `-bin` / `-git` matrix (+ deb/rpm/Chocolatey); release CD gated on green CI
2. [x] **Doctor / purge / uninstall: dual systemd scopes** — Phase 4m; legacy Bash + `install.sh` clean system **and** user units
3. [ ] **MCP → Go CLI** — Phase 5; retire Python dispatcher
4. [ ] **Graduate commands** — dual-OS CI + delete dual libs per [graduation rule](#command-graduation-rule)

---

## Progress by command

### Dispatcher / meta

| Surface | Status | Package / notes |
| --- | --- | --- |
| `version` / `-V` / help / suggestions | Done | `internal/version`, `internal/suggest` |
| Unknown command suggest | Done | — |

### `schedule`

| Surface | Status | Notes |
| --- | --- | --- |
| `config get\|set\|list` | Done | `internal/config` |
| `status` | Done | Reports system and user scopes |
| `enable\|disable --dry-run` | Done | Shows chosen scope |
| `enable\|disable` live (Linux systemd) | Done | Prefers **system**; `--system` / `--user`; migrates other scope — see [policy](#systemd-system-vs-user) |
| `enable\|disable` live (macOS / cron) | Done | launchd / crontab |
| `enable\|disable` live (Windows) | Done | Admin Task Scheduler via PowerShell register/unregister |
| `setup` | Done | Interactive wizard; writes config; optional native enable (`--system`/`--user`/`--cron`) |
| `pre-update` / `post-update` | Done | Unix/macOS only; `MILLENNIUM_SCHEDULER=1` gate; Steam close/relaunch + diag verify |

### `theme`

| Surface | Status | Notes |
| --- | --- | --- |
| `list` [`--json`] | Done | `internal/theme` |
| `install` / `update` / `remove` | Done | Zip-slip safe; `--dry-run` / `--yes` |

### `diag`

| Surface | Status | Notes |
| --- | --- | --- |
| Default report | Done | `internal/diag` |
| `--json` | Done | Contract-shaped fields |
| `--share` | Done | Redact + paste.rs |
| `logs` (no follow) | Done | Updater + Steam WebHelper |
| `doctor --dry-run` | Done | Plan only |
| `doctor` / `--fix` live | Done | Upgrade/hooks/flatpak/schedule/skins/linger/permissions; package sync still advisory |
| `logs --follow` | Done | Filter-tail newest Steam log (+ updater headline) |

### `upgrade`

| Surface | Status | Notes |
| --- | --- | --- |
| `--rollback list` | Done | `internal/upgrade` |
| `--dry-run` (local + remote resolve) | Done | — |
| Remote download + SHA | Done | `internal/githubapi` |
| Extract/install when writable | Done | Writable lib / Windows Steam; else Linux `sudo` re-exec |
| `--file` SHA gate | Done | Fail-closed before install |
| `--rollback <id>` apply | Done | Unix swap + Windows restore when writable; else Linux `sudo` |
| Non-root Linux → `/usr/lib` | Done | Download/verify as user, then `sudo` handoff (native under root) |

### `purge` / `repair`

| Surface | Status | Notes |
| --- | --- | --- |
| `purge --dry-run` | Done | `internal/purge` |
| `purge` live Unix | Done | Confirm / `--yes` |
| `purge` live Windows | Done | millennium/wsock/backups/config + Task Scheduler; Steam/-Yes |
| `repair --dry-run` | Done | `internal/repair` |
| `repair` live (user paths) | Partial | chown/htmlcache native; hook/binary reinstall may still need legacy |

### MCP / packaging

| Surface | Status | Notes |
| --- | --- | --- |
| MCP server | Legacy | `scripts/millennium-mcp.py` |
| Installers ship Go binary first | Done | Unix `install.sh` + Windows `install.ps1`; release embeds `millennium` / `millennium.exe` in versioned OS/arch archives; shell/PS fallback remains |
| Dual `.sh` / `.ps1` libs removed | Not started | Only after graduation |

---

## Phases (detail)

### Phase 0 — Spec + gate — Done

- [x] [`spec/cli-contract.yaml`](../spec/cli-contract.yaml)
- [x] [`scripts/ci/check-cli-contract.py`](../scripts/ci/check-cli-contract.py)
- [x] Wired into `make lint`

### Phase 1 — MVP strangler — Done

- [x] Go module under [`go/`](../go/)
- [x] Native version / help / suggestions
- [x] Other commands exec legacy (`internal/legacy`)
- [x] `make build` / `make test-go` / CI workflow

### Phase 2 — Config + read-mostly — Done

- [x] `schedule config` get/set/list
- [x] `theme list` (+ `--json`)
- [x] Bare / quiet `diag` summary

### Phase 3 — Mutating core — Done

Exit when upgrade / repair / purge / doctor are natively usable on both OSes
with `MILLENNIUM_LEGACY=1` only as escape hatch.

- [x] Upgrade: rollback list/apply, dry-run, download+SHA, install when writable
- [x] Upgrade: non-root Linux system install / rollback via `sudo` handoff
- [x] Purge: dry-run + Unix live + Windows live
- [x] Repair: dry-run + user-path live
- [x] Diag: `--json`, `--share`, `logs`, doctor dry-run + live, `--follow`

### Phase 4 — Schedule + installers — Done

- [x] Schedule status + Unix enable/disable (+ dry-run everywhere)
- [x] Linux **system** + **user** systemd service/timer (prefer system; `--system` / `--user`; migrate other scope)
- [x] Theme install/update/remove (companion slice)
- [x] Windows schedule enable/disable live (Task Scheduler)
- [x] `pre-update` / `post-update` (Unix/macOS; Steam capture/close/relaunch + diag)
- [x] `schedule setup` wizard → native enable (honors `--system` / `--user` / `--cron`)
- [x] Unix `install.sh` Go-first PATH `millennium` (`make build` / prebuilt; shell fallback)
- [x] Windows `install.ps1` prefers `millennium.exe`; release CD embeds Go in versioned OS/arch archives
- [x] Packaging matrix: from-source / `-bin` / `-git` (+ deb/rpm/Chocolatey recipes)
- [x] **Phase 4m:** Doctor / purge / uninstall clean **both** systemd scopes on legacy Bash paths (`disable_timer`, `install.sh` uninstall without `runuser` privilege drop, purge prefers `millennium schedule disable`); diag detects system timers

### Systemd system vs user

Linux when systemd is available (non-`--cron`):

| Preference | When |
| --- | --- |
| **System** (`/etc/systemd/system`, `systemctl` without `--user`) | Preferred when this process can write system units (typically root). Avoids linger for headless updates. |
| **User** (`~/.config/systemd/user`, `systemctl --user`) | Fallback when system units are unavailable. Linger tip still printed. |

Shipped behavior:

1. **Selection:** auto prefers system; `--system` / `--user` force; mutual exclusion.
2. **Units:** `millennium-update.service` / `.timer`; system scope sets `User=` / `Group=` / `HOME=` from `SUDO_USER` (or current user).
3. **Status / disable (Go):** probe and clear both scopes (system skip if unprivileged).
4. **Enable (Go):** removes the other scope when possible before writing.
5. **Legacy Bash:** `disable` / enable-migration / uninstall clear both scopes; Bash enable still writes user units until graduated.
6. **macOS / Windows / cron:** unchanged.

### Phase 5 — MCP + cleanup — Not started

**Definition of done:**

- [ ] Every contract feature implemented **once** in Go
- [ ] Every [parity matrix](unification-audit.md#parity-matrix) row green
- [ ] Bash / Pester suites retired only after Go dual-OS suite supersedes them
- [ ] CONTRIBUTING “Linux / Windows parity” checklist → contract + Go CI
- [ ] `make check-all` includes contract check, `go test ./...`, and dual-OS
      behavioral jobs against the Go binary
- [ ] MCP invokes Go CLI (or Go-native tools); dual libs removable

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
- [ ] This roadmap progress tables updated
- [ ] Parity matrix row updated in [unification-audit.md](unification-audit.md)
- [ ] Completions / man / MCP updated if the user surface changed
- [ ] CHANGELOG note for the slice

---

## Parity policy

- User-facing features match across supported OSes.
- OS-shaped *implementations* (systemd vs Task Scheduler, sudoers vs UAC) are
  adapters, not product forks.
- Silent gaps are forbidden. Contract-marked **OS-only** knobs (e.g.
  `schedule --cron`) are the only exceptions — see the audit.

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

## Key artifacts

| Artifact | Role |
| --- | --- |
| [`spec/cli-contract.yaml`](../spec/cli-contract.yaml) | Source of truth for commands / flags / platforms |
| [`scripts/ci/check-cli-contract.py`](../scripts/ci/check-cli-contract.py) | Drift gate |
| [`go/`](../go/) | Strangler CLI (`cmd/millennium` + `internal/*`) |
| `make build` / `make test-go` / `make check-cli-contract` | Local DX |

---

## Related

- [Docs index](README.md) · [Unification audit](unification-audit.md) · [CLI contract](../spec/cli-contract.yaml)
- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [Release runbook](release_runbook.md) · [MCP](mcp.md)
