# Release Runbook

Checklist for cutting a `vX.Y.Z` release of Millennium Helpers. Follow in order; do not tag until the preflight gates pass locally.

For packaging/automation background, see [CONTRIBUTING.md](../CONTRIBUTING.md#versioning).
Full docs index: [README.md](README.md). Licensing / release payload notice:
[licensing.md](licensing.md) (Linux/Windows assets must include
`third_party/MILLENNIUM-LICENSE.md`).

---

## 0. Preconditions

- [ ] Working tree is clean except for intentional release changes
- [ ] On `main`, up to date with `origin/main`
- [ ] You know the target version (semver; bump minor for features, patch for fixes)
- [ ] `PACKAGING_PAT` is configured in repo secrets (required for auto packaging PR + publish).
  Verify (repo admin): Settings → Secrets and variables → Actions → `PACKAGING_PAT` exists.
  Optional smoke: `gh workflow run "CD: Deployment & Release Automation" -f tag_name=v-draft -f skip_ci_gate=true`
  and confirm the packaging job does not fail with a missing-secret error (cancel after that check if desired).
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
make check-version         # VERSION ↔ Scoop / Winget / Homebrew / Arch / Nix / deb / rpm / Chocolatey / .SRCINFO
make check-packaging       # Scoop/Winget/Chocolatey/deb/rpm/Formula structural matrix
make check-man             # every command has a man page
make check-docs            # docs index / Related footers / man / licensing cross-links
make check-licensing       # alias for check-docs
make check-winget          # Winget manifest structure
make check-completions
```

Arch packaging helpers (also run via pre-commit when relevant):

```bash
make sync-git-srcinfo      # -git .SRCINFO from PKGBUILD (recipe changes only)
make sync-stable-srcinfo   # from-source package .SRCINFO from PKGBUILD
make sync-bin-srcinfo      # -bin package .SRCINFO from PKGBUILD
```

With `pre-commit install` + `pre-commit install --hook-type pre-push`, from-source/`-bin`
`.SRCINFO` (and `-git` when that recipe changes) sync on commit, and `make lint`
(includes `check-version`) runs on every push (see [CONTRIBUTING.md § Versioning](../CONTRIBUTING.md#versioning)).
Do **not** bump Arch `-git` `pkgver` on every commit — `pkgver()` is authoritative at `makepkg` time.

---

## 2. Version bump

Use the automated pre-tag bump — do **not** hand-edit packaging version fields or `.SRCINFO`.

```bash
make bump-version VERSION=X.Y.Z
# then edit CHANGELOG.md under ## [X.Y.Z] - YYYY-MM-DD
make check-version
```

Details (what each file gets, hash timing, tip-of-main exclusions):
[CONTRIBUTING.md § Versioning](../CONTRIBUTING.md#versioning).

| File | What changes |
| --- | --- |
| `VERSION` | `X.Y.Z` (via `bump-version`) |
| `pyproject.toml` | `version = "X.Y.Z"` (via `bump-version`) |
| `CHANGELOG.md` | Move notes under `## [X.Y.Z] - YYYY-MM-DD` (**manual**) |
| `Formula/millennium-helpers.rb` | tag archive URL (sha256 later via packaging PR) |
| `Formula/millennium-helpers-bin.rb` | Linux release tarball URL (sha256 later) |
| `packaging/scoop/millennium-helpers.json` | `version` + tag zip URL |
| `packaging/scoop/millennium-helpers-bin.json` | `version` + Windows zip URL |
| `packaging/winget/*.yaml` | `PackageVersion` + installer URL / `ReleaseDate` |
| `packaging/winget-git/*.yaml` | Tip-of-main only (`0.0.0-git`); **not** bumped with `VERSION` |
| `packaging/millennium-helpers/{PKGBUILD,.SRCINFO}` | from-source `pkgver` + tag archive |
| `packaging/millennium-helpers-bin/{PKGBUILD,.SRCINFO}` | `-bin` `pkgver` + Linux tarball |
| `packaging/deb/**`, `packaging/rpm/**`, `packaging/chocolatey/**` | package versions (hashes later where pinned) |
| `nix/release-info.nix` | `version` (`srcAssetHash` / `srcGitHash` later via packaging PR) |

Hashes stay on the previous release until the tag’s packaging PR runs
`update-packaging-versions.sh`. Nix/Arch CI may notice “Release asset not published yet” and
skip the `-bin` tarball build until after the tag — that is expected.

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
SHA="$(git rev-parse HEAD)"
gh run list --commit "$SHA" --limit 30

# Required for the release CD gate (must be success on this SHA before/when tagging):
for wf in test-suite.yml shellcheck.yml completions.yml; do
  echo "=== $wf ==="
  gh run list --commit "$SHA" --workflow "$wf" --limit 3
done

# Strongly recommended before tagging:
for wf in homebrew.yml version-sync.yml package-manifests.yml powershell-lint.yml; do
  echo "=== $wf ==="
  gh run list --commit "$SHA" --workflow "$wf" --limit 3
done

# Investigate failures:
# gh run view <run-id> --log-failed
```

Critical workflows for a release commit:

- **CI: Shell Script Linting** (ShellCheck) — must pass (**CD gate**)
- **CI: Cross-Platform Test Suite** — must pass (**CD gate**)
- **CI: Shell Completions Validation** — must pass (**CD gate**)
- **CI: Packaging Version Sync**
- **CI: Homebrew Formula Validation**
- **CI: PowerShell Script Analysis**
- **CI: Package Manifests Validation** / Windows package install / PKGBUILD / Nix / man pages as applicable

Do **not** tag while ShellCheck, the Test Suite, or Completions CI is red.

---

## 5. Tag and push

```bash
git tag -a "vX.Y.Z" -m "vX.Y.Z"
git push origin "vX.Y.Z"
```

This starts **CD: Deployment & Release Automation**, which:

1. Waits for **Test Suite + ShellCheck + Completions** success on that commit SHA
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
- [ ] `main` Formula / Scoop / Winget / versioned Arch hashes match the published assets (`make check-version`)
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

# Pre-tag packaging bump (see CONTRIBUTING.md#versioning):
make bump-version VERSION=X.Y.Z
# edit CHANGELOG.md under ## [X.Y.Z] - YYYY-MM-DD

make check-version
make lint
make test

git add -A && git commit -m "release: vX.Y.Z …" && git push origin main
SHA="$(git rev-parse HEAD)"
gh run list --commit "$SHA" --limit 30
for wf in test-suite.yml shellcheck.yml completions.yml; do
  gh run list --commit "$SHA" --workflow "$wf" --limit 3
done
# wait until those three are success, then:

git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z
gh run list --workflow release.yml --limit 3
```

## Related

- **Docs index:** [README.md](README.md)
- **Project:** [README.md](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [SECURITY.md](../SECURITY.md) · [CHANGELOG.md](../CHANGELOG.md)
- **Guides:** [licensing.md](licensing.md) · [mcp.md](mcp.md) · [security_troubleshooting.md](security_troubleshooting.md)
