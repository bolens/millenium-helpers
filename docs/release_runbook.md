# Release Runbook

Checklist for cutting a `vX.Y.Z` release of Millennium Helpers. Follow in order; do not tag until the preflight gates pass locally.

For packaging/automation background, see [CONTRIBUTING.md](../CONTRIBUTING.md#versioning).

---

## 0. Preconditions

- [ ] Working tree is clean except for intentional release changes
- [ ] On `main`, up to date with `origin/main`
- [ ] You know the target version (semver; bump minor for features, patch for fixes)
- [ ] `PACKAGING_PAT` is configured in repo secrets (required for auto packaging PR + publish)
- [ ] Dev tools installed per [CONTRIBUTING.md § Development requirements](../CONTRIBUTING.md#development-requirements)
  (`make setup`, plus **`pwsh`** for Windows tests; **Docker** if you will run `make test-all-distros`)

---

## 1. Local preflight (required)

Run these from the repo root. **Do not skip lint/shellcheck.**

```bash
# Install shellcheck + ruff if needed (see CONTRIBUTING for pwsh / Docker / shells)
make setup

# ShellCheck + ruff + VERSION/man/completions gates
make lint

# Full local unit + behavioral suite
make test

# Windows Pester (requires pwsh + Pester module)
make test-windows

# Optional but recommended before a major/minor release:
# Dockerized Debian / Ubuntu / Fedora runs (needs Docker)
make test-all-distros
```

`make check-all` is shorthand for `make lint` + `make test`. Prefer running `make test-windows` as well before tagging. If `pwsh` or Docker is missing, install them (or use the Dev Container) rather than skipping those gates for a release.

Extra packaging gates (also covered by some CI workflows):

```bash
make check-version    # VERSION ↔ Scoop / Winget / Homebrew URLs
make check-man        # every command has a man page
make check-winget     # Winget manifest structure
make check-completions
```

If Arch packaging files changed:

```bash
make sync-pkgver
```

---

## 2. Version bump

Update all versioned surfaces together:

| File | What to change |
| --- | --- |
| `VERSION` | `X.Y.Z` |
| `CHANGELOG.md` | Move notes under `## [X.Y.Z] - YYYY-MM-DD` |
| `pyproject.toml` | `version = "X.Y.Z"` |
| `Formula/millennium-helpers.rb` | `releases/download/vX.Y.Z/...` URL (sha256 updated later by packaging PR) |
| `packaging/scoop/millennium-helpers.json` | `version` + Windows zip URL |
| `packaging/winget/*.yaml` | `PackageVersion` + installer URL / `ReleaseDate` |

Keep existing SHA256s for now if assets are not published yet. `make check-version` only requires version strings and URL shape.

```bash
make check-version
```

---

## 3. Commit on main

```bash
git add -A
git status   # review: no secrets, no build artifacts
git commit -m "$(cat <<'EOF'
release: vX.Y.Z <short summary>

EOF
)"
git push origin main
```

---

## 4. Wait for CI on the release commit

Before tagging, confirm the push to `main` is green (or understand any expected failures).

```bash
gh run list --branch main --limit 20
# Investigate failures:
gh run view <run-id> --log-failed
```

Critical workflows for a release commit:

- **CI: Shell Script Linting** (ShellCheck) — must pass
- **CI: Cross-Platform Test Suite** — must pass (release gate waits on this for the tag SHA)
- **CI: Shell Completions Validation**
- **CI: Packaging Version Sync**
- **CI: Homebrew Formula Validation**
- **CI: PowerShell Script Analysis**
- **CI: Package Manifests Validation** / Windows package install / PKGBUILD / Nix / man pages as applicable

Do **not** tag while ShellCheck or the Test Suite is red.

---

## 5. Tag and push

```bash
git tag -a "vX.Y.Z" -m "vX.Y.Z"
git push origin "vX.Y.Z"
```

This starts **CD: Deployment & Release Automation**, which:

1. Waits for Test Suite success on that commit SHA
2. Builds trimmed Linux/Windows assets + checksums
3. Creates a **draft** GitHub release
4. Opens a packaging PR with real SHA256s
5. Auto-merges the packaging PR and publishes the draft when packaging CI is green

Monitor:

```bash
gh run list --workflow release.yml --limit 5
gh release list --limit 3
gh pr list --search "packaging" --state open
```

---

## 6. After packaging PR merges

- [ ] Draft release is **published** (not still draft)
- [ ] `gh release view vX.Y.Z` shows both archives and `.sha256` sidecars
- [ ] `main` Formula / Scoop / Winget hashes match the published assets (`make check-version`)
- [ ] Spot-check: piped installer dry-run or `brew audit` / Scoop manifest sanity

---

## 7. If something fails mid-release

| Failure | Action |
| --- | --- |
| Local lint/tests fail | Fix before tagging |
| CI red on `main` after bump | Fix forward on `main`; do not tag yet |
| Tag already pushed, CI red | Fix on `main`, then move the tag: `git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z && git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z` (only if the draft was never published) |
| Draft exists, packaging PR CI fails | Fix packaging on the PR branch; merge manually; publish draft with `gh release edit vX.Y.Z --draft=false` |
| `PACKAGING_PAT` missing | Draft assets may still upload; finish packaging PR + publish manually |

Never force-push `main`. Prefer a new patch tag (`vX.Y.Z+1`) if the draft was already published with bad assets.

---

## Quick copy-paste (happy path)

```bash
# Tools: see CONTRIBUTING.md#development-requirements (pwsh, Docker, shellcheck, …)
make setup
make check-all
make test-windows
# make test-all-distros   # optional cross-distro Docker

# … bump VERSION / CHANGELOG / packaging URLs …

make check-version
make lint
make test

git add -A && git commit -m "release: vX.Y.Z …" && git push origin main
gh run list --branch main --limit 15   # wait for green

git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z
gh run list --workflow release.yml --limit 3
```
