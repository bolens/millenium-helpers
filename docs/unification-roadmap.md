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
| **5 — MCP + cleanup** | Done | Native Go MCP + `--register` + PATH twin; Python escape hatch remains |
| **6 — Graduation** | In progress | Through **6ad**: meta/schedule/theme/purge/diag/repair peeled; upgrade long-name thin-wrap (dual libs for install handoff); MCP graduated; **Endgame A–C** next |

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
| Graduated | Native Go + dual-OS CI gate; legacy may remain until a later peel-off PR |
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
3. [x] **MCP prefer Go for non-elevate** — Phase 5a; Python façade → `millennium <cmd>` when present
4. [x] **MCP elevate via Go + sudoers** — Phase 5b; verb-restricted sudoers; MCP elevates Go dispatcher
5. [x] **Native Go MCP server (5c.1)** — `millennium mcp` owns stdio JSON-RPC; Python prefer-exec + `--register`
6. [x] **Go MCP `--register` + packaging entry** — Phase 5c; PATH `millennium-mcp` = Go argv0 twin; Python lib escape hatch
7. [x] **Phase 6a dual-OS graduation gate** — `check-all` → `test-go`; `go.yml` Windows+Linux dispatcher smokes; meta surface graduated
8. [x] **Phase 6b schedule config graduated** — dual-OS `go.yml` set/get/list smoke; dual libs kept until peel
9. [x] **Phase 6c schedule config peel** — long-name `config` thin-wraps to Go; `schedule_config.sh` / `ScheduleConfig.ps1` removed
10. [x] **Phase 6d theme list graduated** — dual-OS `go.yml` list/`--json` smoke; dual libs kept until peel
11. [x] **Phase 6e theme list peel** — long-name `list` thin-wraps to Go; mutate stays on `theme_ops` / ThemeOps
12. [x] **Phase 6f theme mutate graduated** — dual-OS offline `go.yml` install/update/remove smoke; dual libs kept until peel
13. [x] **Phase 6g theme mutate peel** — long-name theme thin-wraps to Go; `theme_ops` / ThemeOps removed
14. [x] **Phase 6h schedule status graduated** — dual-OS `go.yml` disabled-status smoke; status dual libs kept until peel
15. [x] **Phase 6i schedule status peel** — long-name `status` thin-wraps to Go; `schedule_status` / ScheduleStatus removed (`rotate_logs` → hooks)
16. [x] **Phase 6j schedule enable/disable dry-run graduated** — dual-OS `go.yml` dry-run smoke; enable/disable dual libs kept until peel
17. [x] **Phase 6k schedule enable/disable peel** — long-name enable/disable → Go; timer/cron/Enable/Disable libs removed; wizard optional-enable via non-exec Go
18. [x] **Phase 6l schedule setup graduated** — dual-OS `go.yml` `FORCE_WIZARD` dry-run smoke; wizard dual libs kept until peel
19. [x] **Phase 6m schedule pre/post-update graduated** — Linux `go.yml` scheduler-gate smoke; hooks dual lib kept until peel
20. [x] **Phase 6n schedule setup peel** — long-name `setup` → Go; wizard dual libs removed; install.sh builds/`millennium schedule setup`
21. [x] **Phase 6o schedule hooks peel** — long-name `pre-update`/`post-update` → Go; `schedule_hooks.sh` removed (schedule fully peeled)
22. [x] **Phase 6p purge dry-run graduated** — dual-OS `go.yml` smoke; purge dual libs kept until peel
23. [x] **Phase 6q upgrade rollback list graduated** — dual-OS `go.yml` smoke; upgrade dual libs kept until peel
24. [x] **Phase 6r purge peel** — long-name → Go; delete `purge_ops` / PurgeOps
25. [x] **Phase 6s upgrade `--dry-run` graduated** — dual-OS offline `--file`+SHA dry-run smoke
26. [x] **Phase 6t upgrade SHA/`--file` verify graduated** — dual-OS fail-closed + pass smoke
27. [x] **Phase 6u upgrade writable rollback-apply graduated** — dual-OS/`MOCK_LIB_DIR` smoke
28. [x] **Phase 6v upgrade long-name thin-wrap** — exec Go; retain upgrade dual libs for `NeedsLegacy` install handoff
29. [x] **Phase 6w diag report/`--json` graduated** — dual-OS smoke
30. [x] **Phase 6x diag `doctor --dry-run` graduated** — dual-OS smoke
31. [x] **Phase 6y diag `logs` graduated** — dual-OS smoke (no-logs path OK)
32. [x] **Phase 6z diag peel** — long-name → Go; delete `diag_*` / `Diag*` feature libs
33. [x] **Phase 6aa MCP stdio graduated** — dual-OS `initialize` smoke; Python hatch retained until explicit retirement
34. [x] **Phase 6ab–6ad repair** — native hooks/force-upgrade + Steam life + themes; dual-OS graduate; peel `repair_ops` / RepairOps
35. [ ] **Endgame A** — installer hard-require Go (no silent shell/PS PATH fallback)
36. [ ] **Endgame B** — delete `dispatcher.sh` / `Dispatcher.ps1` + shell `millennium` entrypoints
37. [ ] **Endgame C** — suite retirement command-by-command
38. [ ] **Parallel** — collapse upgrade `NeedsLegacy` install handoff; MCP Python hatch retirement

---

## Progress by command

### Dispatcher / meta

| Surface | Status | Package / notes |
| --- | --- | --- |
| `version` / `-V` / help / suggestions | Graduated | `internal/version`, `internal/suggest`; dual-OS `go.yml` + `main_test` |
| Unknown command suggest | Graduated | Same gate as version/help |

### `schedule`

| Surface | Status | Notes |
| --- | --- | --- |
| `config get\|set\|list` | Graduated | `internal/config`; dual-OS `go.yml` smoke; long-name helpers thin-wrap to Go (Phase 6c peel) |
| `status` | Graduated | dual-OS `go.yml` smoke; long-name thin-wrap to Go (Phase 6i peel) |
| `enable\|disable` (dry-run + live) | Graduated | dual-OS dry-run smoke; long-name thin-wrap to Go (Phase 6k peel); dual enable libs removed |
| `setup` | Graduated | dual-OS `FORCE_WIZARD` dry-run smoke; long-name thin-wrap to Go (Phase 6n peel); wizard dual libs removed |
| `pre-update` / `post-update` | Graduated | Linux gate smoke; long-name thin-wrap to Go (Phase 6o peel); hooks dual lib removed |

### `theme`

| Surface | Status | Notes |
| --- | --- | --- |
| `list` [`--json`] | Graduated | `internal/theme`; long-name helpers thin-wrap to Go (Phase 6e/6g) |
| `install` / `update` / `remove` | Graduated | Zip-slip safe; long-name thin-wrap to Go; `theme_ops` / ThemeOps removed (Phase 6g) |

### `diag`

| Surface | Status | Notes |
| --- | --- | --- |
| Default report | Graduated | dual-OS `go.yml` smoke (Phase 6w); long-name thin-wrap (6z) |
| `--json` | Graduated | dual-OS smoke with report (Phase 6w) |
| `--share` | Done | Redact + paste.rs |
| `logs` (no follow) | Graduated | dual-OS smoke / no-logs path (Phase 6y) |
| `doctor --dry-run` | Graduated | dual-OS smoke (Phase 6x) |
| `doctor` / `--fix` live | Done | Upgrade/hooks/flatpak/schedule/skins/linger/permissions; package sync still advisory |
| `logs --follow` | Done | Filter-tail newest Steam log (+ updater headline) |

### `upgrade`

| Surface | Status | Notes |
| --- | --- | --- |
| `--rollback list` | Graduated | dual-OS `go.yml` smoke (Phase 6q) |
| `--dry-run` (local + remote resolve) | Graduated | dual-OS offline `--file`+SHA smoke (Phase 6s) |
| Remote download + SHA | Done | `internal/githubapi` |
| Extract/install when writable | Done | Writable lib / Windows Steam; else Linux `sudo` re-exec |
| `--file` SHA gate | Graduated | dual-OS fail-closed + pass (Phase 6t) |
| `--rollback <id>` apply | Graduated | dual-OS writable smoke (Phase 6u); else Linux `sudo` |
| Non-root Linux → `/usr/lib` | Done | Download/verify as user, then `sudo` handoff (native under root) |
| Long-name entrypoint | Thin-wrap | Phase 6v: prefers Go; `MILLENNIUM_LEGACY=1` keeps upgrade dual libs for install handoff |

### `purge` / `repair`

| Surface | Status | Notes |
| --- | --- | --- |
| `purge --dry-run` | Graduated | dual-OS `go.yml` smoke (Phase 6p); dual libs removed (6r) |
| `purge` live Unix | Graduated | Confirm / `--yes`; long-name thin-wrap (6r) |
| `purge` live Windows | Graduated | millennium/wsock/backups/config + Task Scheduler; Steam/-Yes |
| `repair --dry-run` | Graduated | dual-OS `go.yml` smoke (Phase 6ac); dual libs removed (6ad) |
| `repair` live | Graduated | Unix hooks + ownership/htmlcache/themes; Windows force-upgrade; Steam/-Yes; long-name thin-wrap (6ad) |

### MCP / packaging

| Surface | Status | Notes |
| --- | --- | --- |
| MCP server | Graduated | dual-OS `initialize` smoke (Phase 6aa); Python hatch (`MILLENNIUM_MCP_PYTHON=1`) retained until explicit retirement |
| Installers ship Go binary first | Done | Unix `install.sh` + Windows `install.ps1`; shell/PS fallback remains (**Endgame A**) |
| Dual `.sh` / `.ps1` libs removed | Partial | Schedule + theme + purge + diag + repair feature libs deleted; upgrade/shared + dispatcher remain until install handoff / Endgame B |

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
5. **Legacy Bash (long-name):** enable/disable/status/setup/hooks thin-wrap to Go (Phase 6k–6o). Feature schedule dual libs removed.
6. **macOS / Windows / cron:** unchanged.

### Phase 5 — MCP + cleanup — Done

- [x] **Phase 5a:** Python MCP prefers Go `millennium <feature>` for non-elevating tools; `MILLENNIUM_MCP_LONGNAMES=1` escape
- [x] **Phase 5b:** Sudoers (install.sh + Arch) allowlist Go `millennium {upgrade,diag,repair,purge}[ *]` plus long-names; MCP elevates via Go; Windows RunAs for `.exe`
- [x] **Phase 5c.1:** Native Go MCP stdio (`millennium mcp`); Python prefer-execs Go (skip under `TEST_SUITE_RUN` / `MILLENNIUM_MCP_PYTHON=1`)
- [x] **Phase 5c:** Go `--register`; PATH `millennium-mcp` installs Go argv0 twin (shim fallback); Python kept as lib escape hatch; Windows `.cmd` → `millennium.exe mcp`

### Phase 6 — Graduation — In progress

- [x] **Phase 6a:** `make check-all` → `lint` + `test-go` + `test`; `go.yml` dual-OS dispatcher smokes (version/help/suggest); Linux-only legacy help smoke retained; CONTRIBUTING parity gate documents Go CI for graduated surfaces
- [x] **Phase 6b:** `schedule config` get/set/list dual-OS Go smoke + graduated mark; `schedule_config.sh` / `ScheduleConfig.ps1` kept for long-name helpers until peel
- [x] **Phase 6c:** Peel schedule-config dual libs — long-name `config` → `millennium schedule config` (`MILLENNIUM_LEGACY=0`); delete Bash/PS config libs; CI builds Go for schedule/MCP suites
- [x] **Phase 6d:** `theme list` (+ `--json`) dual-OS Go smoke + graduated mark; `theme_ops` / long-name list bodies kept until peel
- [x] **Phase 6e:** Peel theme list — long-name `list` → `millennium theme list` (`MILLENNIUM_LEGACY=0`); mutate dual libs retained
- [x] **Phase 6f:** `theme install` / `update` / `remove` dual-OS offline Go smoke + graduated mark; dual libs kept until peel
- [x] **Phase 6g:** Peel theme mutate — entire long-name theme → Go (`MILLENNIUM_LEGACY=0`); delete `theme_ops.sh` / `ThemeOps.ps1`
- [x] **Phase 6h:** `schedule status` dual-OS Go smoke + graduated mark; `schedule_status` dual libs kept until peel
- [x] **Phase 6i:** Peel schedule status — long-name `status` → Go (`MILLENNIUM_LEGACY=0`); delete status dual libs; `rotate_logs` lives in `schedule_hooks.sh`
- [x] **Phase 6j:** `schedule enable|disable --dry-run` dual-OS Go smoke + graduated mark; enable/disable dual libs kept until peel
- [x] **Phase 6k:** Peel schedule enable/disable — long-name → Go (`MILLENNIUM_LEGACY=0`); delete `schedule_timer`/`schedule_cron`/`ScheduleEnable`/`ScheduleDisable`; wizard optional-enable invokes Go without exec/exit
- [x] **Phase 6l:** `schedule setup` dual-OS Go smoke (`FORCE_WIZARD` + dry-run) + graduated mark; wizard dual libs kept until peel
- [x] **Phase 6m:** `schedule pre-update`/`post-update` Linux Go smoke (`MILLENNIUM_SCHEDULER=1`) + graduated mark; hooks dual lib kept until peel
- [x] **Phase 6n:** Peel schedule setup — long-name → Go; delete `schedule_wizard.sh` / `ScheduleWizard.ps1`; install wizard uses `bin/millennium schedule setup`
- [x] **Phase 6o:** Peel schedule hooks — long-name → Go; delete `schedule_hooks.sh` (schedule feature dual libs gone)
- [x] **Phase 6p:** `purge --dry-run` dual-OS Go smoke + graduated mark; purge dual libs kept until peel
- [x] **Phase 6q:** `upgrade --rollback list` dual-OS Go smoke + graduated mark; upgrade dual libs kept until peel
- [x] **Phase 6r:** Peel purge — long-name → Go; delete `purge_ops.sh` / `PurgeOps.ps1`
- [x] **Phase 6s:** `upgrade --file`+SHA `--dry-run` dual-OS Go smoke + graduated mark
- [x] **Phase 6t:** upgrade SHA/`--file` verify fail-closed + pass dual-OS smoke + graduated mark
- [x] **Phase 6u:** writable rollback-apply dual-OS Go smoke + graduated mark
- [x] **Phase 6v:** long-name upgrade thin-wrap → Go; `legacy.RunLegacy` sets `MILLENNIUM_LEGACY=1` so upgrade dual libs remain for install handoff
- [x] **Phase 6w:** `diag` report/`--json` dual-OS Go smoke + graduated mark
- [x] **Phase 6x:** `diag doctor --dry-run` dual-OS Go smoke + graduated mark
- [x] **Phase 6y:** `diag logs` dual-OS Go smoke + graduated mark
- [x] **Phase 6z:** Peel diag — long-name → Go; delete `diag_*.sh` / `Diag*.ps1`
- [x] **Phase 6aa:** MCP `initialize` dual-OS smoke + graduated mark; Python hatch retained
- [x] **Phase 6ab:** Repair Partial → Done — native Unix hooks, Windows force-upgrade, Steam lifecycle, sudo chown, theme refresh
- [x] **Phase 6ac:** `repair --dry-run` (+ Linux mock live hooks) dual-OS Go smoke + graduated mark
- [x] **Phase 6ad:** Peel repair — long-name → Go; delete `repair_ops.sh` / `RepairOps.ps1`
- [ ] **Endgame A:** installer hard-require Go (drop silent shell/PS PATH fallback)
- [ ] **Endgame B:** delete `dispatcher.sh` / `Dispatcher.ps1` + shell `millennium` entrypoints
- [ ] **Endgame C:** suite retirement command-by-command
- [ ] Collapse upgrade `NeedsLegacy` install handoff; MCP Python hatch retirement (parallel)
- [ ] Every contract feature implemented **once** in Go
- [ ] Every [parity matrix](unification-audit.md#parity-matrix) row green / graduated
- [ ] Bash / Pester suites retired only after Go dual-OS suite supersedes them
- [ ] Dual libs removable after per-command graduation

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
| `make build` / `make test-go` / `make check-all` / `make check-cli-contract` | Local DX (`check-all` = lint + test-go + test) |

---

## Related

- [Docs index](README.md) · [Unification audit](unification-audit.md) · [CLI contract](../spec/cli-contract.yaml)
- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [Release runbook](release_runbook.md) · [MCP](mcp.md)
