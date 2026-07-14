# Changelog

All notable changes to Millennium Helpers are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Packaging three-variant matrix (from-source / `-bin` / `-git`) for Arch, Homebrew, Scoop, Nix; plus deb, rpm, and Chocolatey recipes ([packaging/README.md](packaging/README.md))
- Release CD builds standalone Go dispatchers and embeds `bin/millennium` / `millennium.exe` in trimmed archives
- Windows `install.ps1` prefers `millennium.exe` when present (Go-first PATH layout)
- Go strangler CLI under `go/` (`make build` → `bin/millennium`): native version/help/suggestions; feature commands exec legacy Bash/PowerShell ([docs/unification-roadmap.md](docs/unification-roadmap.md))
- **Phase 2 native paths:** `millennium schedule config` get/set/list, `millennium theme list` (`--json`), read-only `millennium diag` summary (doctor/json/share still legacy; `MILLENNIUM_LEGACY=1` forces legacy)
- **Phase 3 hybrid mutate paths:** `upgrade --rollback list` + remote download/SHA + local `--file` verify / dry-run; `purge` Unix live + `--dry-run`; `repair` user-path live + `--dry-run`; extract/install/rollback apply and Windows live purge still legacy
- **Phase 4a schedule:** `schedule status`, `enable`/`disable --dry-run`, Unix live systemd/launchd/cron enable/disable; Windows live enable/disable and setup still legacy
- **Phase 4b themes:** native `theme install` / `update` / `remove` (zip-slip safe; `--dry-run` / `--yes`)
- **Phase 4c schedule Windows:** native Task Scheduler `enable`/`disable` (admin; quoting parity with `ScheduleEnable.ps1`); setup / pre-post still legacy
- **Phase 4d upgrade rollback:** native `--rollback <id>` apply when writable (Unix `millennium.bak_*` swap; Windows `millennium_backups` restore + Steam/-Yes); dry-run; non-root `/usr/lib` still legacy
- **Phase 4e schedule systemd scopes:** Linux enable/disable/status support **system** and **user** units; auto prefers system when writable; `--system` / `--user`; migrates the other scope; MCP/completions/man updated
- **Phase 4f upgrade sudo handoff:** non-root Linux download+verify then re-exec via `sudo` for install/rollback (keeps verified `--file`/`--sha256`); writability-based install gate
- **Phase 4g purge Windows:** native live purge (Steam millennium/wsock/backups, helper config, MillenniumUpdate task; schedule disable; Steam/-Yes)
- **Phase 4h diag doctor live:** native live repairs (upgrade --force, hooks, flatpak, schedule enable, skins, linger, permissions); `--yes` to stop Steam; package/completions cleanup remains advisory
- **Phase 4i diag logs --follow:** native filter-tail of newest Steam log (Millennium keywords; Ctrl+C); updater log headline; Phase 3 mutating core complete
- **Phase 4j schedule hooks:** native `pre-update` / `post-update` (Unix/macOS): `MILLENNIUM_SCHEDULER=1` gate, log rotate, game abort (75), Steam capture/close/relaunch, diag verify; setup wizard still legacy
- **Phase 4k schedule setup:** native interactive wizard (channel/timer/PAT); merges config preserving `backup_*`; optional enable via native path (`--system`/`--user`/`--cron`); `FORCE_WIZARD` + dry-run
- **Phase 4l Unix install Go-first:** `install.sh` installs `bin/millennium` (build via `make build` when needed) as PATH `millennium`; long-name helpers unchanged; Bash dispatcher fallback; `MILLENNIUM_INSTALL_DISPATCHER=shell` escape
- **Phase 4m dual systemd scopes (legacy):** Bash `schedule disable` / enable migration, purge, doctor, and `install.sh` uninstall clear **system and user** `millennium-update` units (no `runuser` drop before disable); diag detects system timers
- **Phase 5a MCP → Go (non-elevate):** `millennium-mcp` prefers `millennium diag|theme|schedule …` when the Go dispatcher is available; doctor/upgrade/repair/purge stay on long-name helpers for sudoers; `MILLENNIUM_MCP_LONGNAMES=1` forces the old path
- **Phase 5b MCP elevate + sudoers:** installer/Arch allowlist Go `millennium {upgrade,diag,repair,purge}`; MCP elevates via Go dispatcher (Windows RunAs for `.exe`); long-name helpers remain for timers / legacy
- **Phase 5c.1 native Go MCP:** `millennium mcp` serves stdio JSON-RPC + tools; Python `millennium-mcp` prefer-execs Go (keeps `--register`); `MILLENNIUM_MCP_PYTHON=1` forces Python; `test_mcp` covers `MCP_IMPL=python|go|both`
- **Phase 5c Go MCP register + PATH entry:** native `--register`; install/packaging ship Go (or shim) as `millennium-mcp` argv0 twin; Python moves to lib escape hatch; Windows `millennium-mcp.cmd` → `millennium.exe mcp`
- **Phase 6a graduation gate:** `make check-all` includes `test-go`; `go.yml` dual-OS dispatcher smokes for version/help/suggest; meta surface marked graduated (no dual-lib deletion)
- **Phase 6b schedule config graduated:** dual-OS `go.yml` smoke for `millennium schedule config` set/get/list; Bash/PS config dual libs retained until peel
- **Phase 6c schedule config peel:** long-name `millennium-schedule config` thin-wraps to Go; removed `schedule_config.sh` / `ScheduleConfig.ps1`; CI builds Go for schedule/MCP behavioral suites
- **Phase 6d theme list graduated:** dual-OS `go.yml` smoke for `millennium theme list` / `--json`; Bash/PS theme dual libs retained until peel
- **Phase 6e theme list peel:** long-name `millennium-theme list` thin-wraps to Go; mutate stays on `theme_ops` / ThemeOps; CI builds Go for theme behavioral/Pester suites
- **Phase 6f theme mutate graduated:** dual-OS offline `go.yml` smoke for `theme install`/`update`/`remove` validation paths; Bash/PS theme dual libs retained until peel
- **Phase 3c diag:** native `--json`, `logs` (non-follow), richer report probes, `doctor --dry-run` plan; live doctor / `--share` / `--follow` still legacy
- **Phase 3d diag share:** native `--share` (home/user/token redaction + paste.rs upload); `--follow` and live doctor still legacy
- **Phase 3e upgrade install:** native tar/zip extract + atomic install when writable (root / `MILLENNIUM_LIB_DIR` / Windows Steam); non-root Linux system path and rollback apply still legacy
- Machine-readable CLI contract [`spec/cli-contract.yaml`](spec/cli-contract.yaml) + `make check-cli-contract` (MCP / man / bash completions drift gate)
- Unification audit + roadmap docs with feature×OS×test parity matrix and command graduation rule

### Changed
- Release CD waits for a broader green CI set (tests, Go, linters, version-sync, manifests, man pages) on the tag SHA before building assets; `skip_ci_gate` is allowed only for `v-draft`
- Release assets are versioned and OS/arch-split (`millennium-helpers-v{VER}-{os}-{arch}…`); from-source packaging uses controlled `-src.tar.gz` / `-src.zip` (no GitHub autoarchive URLs; no legacy unversioned aliases)
- AUR-standard naming: plain `millennium-helpers` = tagged from-source; `millennium-helpers-bin` = release assets; Nix default package is from-source
- Modularization: feature libraries for schedule/theme/upgrade/repair/purge and the top-level `millennium` dispatcher on Linux and Windows; Windows `common.ps1` split into `scripts/windows/lib/*.ps1` (sourced by retained `common.ps1`)
- Removed thin diag aggregators (`scripts/lib/diag.sh`, `scripts/windows/lib/Diag.ps1`); orchestration lives in `millennium-diag` entrypoints; report API is `DiagReport.ps1`
- Bash upgrade completions include `--sha256`, `--insecure-skip-verify`, and `--all-users`

## [2.6.2] - 2026-07-10

### Fixed
- Windows↔Unix parity: schedule `config` under StrictMode; scheduled task uses `-Yes -Quiet`, theme update, and `updater.log`
- Windows upgrade honors `backup_max_age_days` and accepts GNU-style channel/force/file/rollback flags
- Windows repair supports `-SkipTheme` / `--skip-theme` and refreshes themes after force reinstall
- Setup wizard (Unix + Windows) preserves `backup_limit` / `backup_max_age_days` when rewriting config

## [2.6.1] - 2026-07-10

### Changed
- Arch `-git` packaging follows AUR VCS policy: no perpetual `pkgver` sync on every commit; `pkgver()` is authoritative at `makepkg` time; `.SRCINFO` regenerates only when the `-git` recipe changes (`make sync-git-srcinfo`)

### Fixed
- Portable packaging CI sed (GNU vs BSD/macOS) and Windows InstallTrack I/O so Cross-Platform Test Suite stays green
- Diag install-track meta no longer breaks when `USERPROFILE` is unset or tests mock `Get-Content`

## [2.6.0] - 2026-07-10

### Added
- Helpers install tracks (`release` / `main` / `tag` / `checkout`) with `install-meta.json`, `--track`/`--tag` (Unix) and `-Track`/`-Tag` (Windows)
- Auto-migrate legacy installs without meta on first install/diag/doctor touch
- Winget tip-of-main manifests (`packaging/winget-git/`, `bolens.millenniumhelpers.git`)
- Millennium client channel `main` (tip-of-development) alongside `stable`/`beta` — separate from helpers track
- Diag JSON fields `helpers_track` / `helpers_ref`; track-aware doctor sync

### Changed
- Doctor and update checks follow the recorded helpers track (pinned tags stay pinned; `-git` packages are not compared to release tags)

### Fixed
- `sync-stable-srcinfo` no longer truncates `.SRCINFO` when `makepkg --printsrcinfo` fails (e.g. missing `install=` file in test trees)

## [2.5.0] - 2026-07-10

### Added
- Versioned Arch package (`packaging/millennium-helpers`) built from the Linux release tarball; release CD bumps pkgver + sha256 alongside Formula/Scoop/Winget/Nix
- Scoop `millennium-helpers-git` nightly manifest (tip of `main` via GitHub archive)
- Nix flake packages: `millennium-helpers` (release tarball) and `millennium-helpers-git` (flake source / latest commit)

### Changed
- Arch `-git` recipe moved to `packaging/millennium-helpers-git/` (AUR-ready layout)

### Fixed
- `millennium-schedule setup` under sudo verifies passwordless rules for the real user (`sudo -U`), matching doctor

## [2.4.0] - 2026-07-10

### Added
- Modular `millennium-diag` libraries on Linux (`scripts/lib/diag_*.sh`) and Windows (`scripts/windows/lib/Diag*.ps1`)
- Install-method detection (pacman/scoop/winget/manual/mixed) with release-tag comparison
- Doctor cleanup of unmanaged leftovers before package-upgrade hints
- PowerShell completion health checks and doctor repair
- `-Yes` / `--yes` auto scoop/winget/pacman package upgrade when helpers are outdated
- JSON fields: `install_method`, `mixed_install_ok`, `helpers_checkout`, `latest_release_tag`, `completions_ok`

### Fixed
- Pacman upgrades no longer blocked by unmanaged completion leftovers; doctor refuses to overwrite package-owned files
- Empty `DIAG_TEST_OBSOLETE_LIST` correctly means “no obsolete candidates” in tests
- Winget package ID uses `bolens.millenniumhelpers`
- Windows PowerShell 5.1 no longer fails to parse diag modules (ASCII-only sources; Scoop profile hook no longer calls `scoop` at profile load)

### Changed
- Thin loaders: Linux `diag.sh` (replaces `diag_report.sh`), Windows `Diag.ps1` (replaces `DiagReport.ps1`)
- Manual installs sync helper scripts from the latest release tarball/zip instead of `main`

## [2.3.0] - 2026-07-10

### Added
- PowerShell Tab completions with installer profile hooks (Windows + Scoop)
- Cross-shell completion tests (bash/zsh/fish/nushell) and nested zsh simulation
- Homebrew bash/zsh completion symlinks and Nushell completion install
- Isolated prefix install/uninstall coverage in `test_install.sh`

### Fixed
- Fish completions no longer ship bare `VERSION_PLACEHOLDER` tokens
- `sudo millennium-schedule` reaches the user systemd bus via shared `sysctl_user`
- Uninstall disables cron as well as systemd/LaunchAgent schedulers
- Windows uninstall removes the `MillenniumUpdate` scheduled task
- Shared library resolution works from Homebrew-style `prefix/bin` layouts
- Cron enable/disable under sudo targets the invoking user's crontab
- PKGBUILD conflict cleanup docs include bare `millennium` artifacts

### Changed
- Linux installer also installs Nushell completions into the user config path
- Release Windows zip includes `completions/powershell/`
- Manual uninstall docs cover PowerShell hooks, state dirs, and Scoop hooks

## [2.2.1] - 2026-07-10

### Security
- Verify SHA256 checksums in piped `install.sh` / `install.ps1` against release `.sha256` sidecars
- Verify SHA256 checksums during Windows `millennium-upgrade` (parity with Linux)
- Restrict Windows `config.json` ACLs when writing `github_token`

### Fixed
- Include `scripts/millennium-mcp.py` in the trimmed Windows release zip / Scoop CI staging
- Update standalone installer tests for trimmed release archive layout
- Republish release assets so packaging checksums match the Windows zip that includes MCP

### Changed
- Wire `test_millennium_dispatcher.sh` and `test_packaging_ci.sh` into the CI matrix
- Slim local `tests/run_tests.sh` to source shared assertions and defer packaging gates to CI

## [2.2.0] - 2026-07-09

See GitHub release notes for v2.2.0.
