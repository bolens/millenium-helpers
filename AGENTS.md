# AGENTS.md

Guidance for coding agents working in this repository. Keep changes focused, preserve
cross-platform behavior, and validate the smallest relevant surface before widening checks.

## Repository overview

Millennium Helpers is a cross-platform Go CLI for installing, upgrading, repairing,
diagnosing, scheduling, and managing themes for Millennium. The GitHub repository name
`millenium-helpers` is intentionally misspelled; the product and executable are
**Millennium** and `millennium`.

- `go/cmd/millennium/`: CLI entry point and command registration.
- `go/internal/`: feature implementations. Prefer shared Go logic with small
  OS-specific files named `*_unix.go`, `*_windows.go`, or `*_stub.go`.
- `spec/cli-contract.yaml`: source of truth for commands, flags, platforms, channels,
  completion/man-page option blocks, and MCP schemas/allowlists.
- `install.sh`: thin Unix bootstrap for the Go installer; do not move feature logic here.
- `completions/`, `man/`: user-facing CLI façades, partly generated from the contract.
- `scripts/ci/`: Python and shell validation, synchronization, packaging, and release tools.
- `tests/`: Bash unit/behavioral tests; `tests/windows/` contains Pester tests.
- `packaging/`, `Formula/`, `nix/`: distribution metadata. See `packaging/README.md`.
- `docs/`: guides indexed by `docs/README.md`.

Read `CONTRIBUTING.md` for detailed workflows and `docs/release_runbook.md` before
release work.

## Working rules

- Inspect the relevant implementation, tests, and contract before editing.
- Preserve unrelated user changes. Do not clean the worktree, rewrite history, or edit
  unrelated files.
- Prefer one cross-platform Go implementation. Isolate genuine OS differences behind
  build-tagged files and keep behavior aligned on Linux, macOS, and Windows.
- Feature commands live in Go only. Do not recreate legacy `scripts/lib` or
  `scripts/windows/lib` feature trees.
- New installs expose only `millennium` on `PATH`. Keep legacy argv0 dispatch working,
  but do not add new long-name executable twins.
- Destructive commands should support `--dry-run` and require confirmation unless
  `--yes`/`-y` is supplied.
- Never expose tokens, credentials, private paths, or unsanitized diagnostic data.
- Do not hand-edit generated regions or Arch `.SRCINFO` files; use the synchronization
  targets below.
- Do not commit build/package artifacts such as `bin/`, `pkg/`, `src/`,
  `*.pkg.tar.*`, `*.deb`, `*.rpm`, `*.nupkg`, or release archives.

## CLI changes

For any command, subcommand, flag, channel, completion, man-page option, or MCP surface:

1. Edit `spec/cli-contract.yaml` first.
2. Run `make sync-cli-facade`.
3. Implement the behavior under `go/`.
4. Update hand-written help, man-page prose/examples, and documentation as needed.
5. Add or update Go tests, including OS-specific seams.
6. Run `make check-cli-contract`.

Help (`-h`/`--help`) must exit zero. Unknown options must show useful usage and exit
non-zero. Mark intentionally platform-specific contract entries with `os_only`.

`make sync-cli-facade` updates marked sections in completions, man pages, and MCP
registration/schema code. Review its diff; do not replace surrounding hand-written prose.

## Code style

- Go: run `gofmt`; follow standard Go conventions; keep packages cohesive and tests
  table-driven where that improves coverage.
- Shell: Bash with `set -euo pipefail`; quote expansions; keep ShellCheck clean.
- Python: Python 3.9+, four-space indentation, Ruff formatting/linting.
- PowerShell: use `Set-StrictMode -Version Latest`; gate diagnostics behind
  `MILLENNIUM_DEBUG` or `-Verbose`.
- All text uses UTF-8, LF endings, a final newline, and no trailing whitespace.
- Follow `.editorconfig`; JSON and Python use four spaces, most other files use two.
- Add dependencies only when the standard library or existing dependencies are
  insufficient. Keep `CGO_ENABLED=0` compatibility.

## Validation

Start with checks closest to the change:

```bash
# Go package or test
cd go && go test ./internal/<package>
cd go && go test ./internal/<package> -run TestName

# Broader Go validation
make test-go
make lint-go

# Shell/install/packaging behavior
make test

# Contract, docs, and generated façades
make check-cli-contract
make check-completions
make check-man
make check-docs

# Packaging metadata
make check-version
make check-packaging
make check-winget

# Windows-specific work (requires pwsh; Pester may be skipped if unavailable)
make test-windows

# Full required local gate
make check-all
```

`make check-all` runs lint, all Go tests, and the Bash suite. It does not run Windows
Pester or the Docker distro matrix. Use `make test-all-distros` only when packaging or
portable shell behavior warrants it and Docker is available.

If a required tool is unavailable, report the skipped check explicitly. Do not claim a
check passed when it was not run.

## Test expectations by change

- Go behavior: add tests beside the package in `go/internal/...`; run the package tests,
  then `make test-go`.
- CLI contract/help/MCP/completions/man pages: run `make sync-cli-facade`,
  `make check-cli-contract`, and the relevant completion/man checks.
- Shell code: run `shellcheck` on touched scripts and the closest Bash suite; use
  `make test` for shared installer behavior.
- Python CI helpers: run `ruff check <files>` and `ruff format --check <files>`, plus
  the helper's associated check.
- Windows paths, profiles, Task Scheduler, or PowerShell completions: add Go/Pester
  coverage and run `make test-windows` when available.
- Documentation: update `docs/README.md`, README “Further reading,” and related-guide
  footers when adding or renaming a guide; run `make check-docs`.
- GitHub workflows: run `bash scripts/ci/run-actionlint.sh`.

## Packaging and versioning

`VERSION` must stay aligned with `pyproject.toml` and stable/release packaging metadata.
Tip-of-main `-git` packages are intentionally not tied to `VERSION`.

- For a release bump use `make bump-version VERSION=X.Y.Z`, then update
  `CHANGELOG.md` manually and run `make check-version`.
- Regenerate Arch metadata with `make sync-stable-srcinfo`,
  `make sync-bin-srcinfo`, or `make sync-git-srcinfo`.
- Do not manually replace release hashes during a normal version bump. Post-tag release
  automation fills asset hashes.
- Keep the distinction between helpers install tracks (`release`, `main`, `tag`,
  `checkout`) and Millennium client channels (`stable`, `beta`, `main`).
- Do not tag or publish a release unless explicitly requested; follow the release
  runbook end to end.

## Completion criteria

Before handing off:

- Review `git diff` for accidental generated churn, artifacts, secrets, and unrelated edits.
- Ensure user-facing behavior, docs, contract, completions, man pages, and MCP surfaces
  agree where applicable.
- State what changed, which checks ran, their results, and any platform/tooling checks
  that remain unverified.
