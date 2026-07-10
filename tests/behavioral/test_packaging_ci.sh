#!/usr/bin/env bash
# Behavioral tests for packaging CI helpers (hash hardening + version bump automation).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"

UPDATE="${REPO_ROOT}/scripts/ci/update-packaging-versions.sh"
BUMP="${REPO_ROOT}/scripts/ci/bump-version.sh"
CHECK="${REPO_ROOT}/scripts/ci/check-version-sync.sh"
SYNC_SRC="${REPO_ROOT}/scripts/ci/sync-stable-srcinfo.sh"
WINGET_CHECK="${REPO_ROOT}/scripts/ci/check-winget-manifests.sh"

# Portable in-place sed (GNU sed -i vs BSD/macOS sed -i '').
sed_inplace() {
  local expr="$1"
  local file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i "$expr" "$file"
  else
    sed -i '' "$expr" "$file"
  fi
}

# Copy packaging surfaces + CI scripts into an isolated tree.
seed_packaging_tree() {
  local dest="$1"
  mkdir -p "$dest/Formula" "$dest/packaging/scoop" "$dest/packaging/winget" \
    "$dest/packaging/millennium-helpers" "$dest/nix" "$dest/scripts/ci"
  cp "$UPDATE" "$BUMP" "$CHECK" "$SYNC_SRC" "$dest/scripts/ci/"
  cp "${REPO_ROOT}/Formula/millennium-helpers.rb" "$dest/Formula/"
  cp "${REPO_ROOT}/packaging/scoop/millennium-helpers.json" "$dest/packaging/scoop/"
  cp "${REPO_ROOT}/packaging/winget/"*.yaml "$dest/packaging/winget/"
  cp "${REPO_ROOT}/packaging/millennium-helpers/PKGBUILD" "$dest/packaging/millennium-helpers/"
  cp "${REPO_ROOT}/packaging/millennium-helpers/.SRCINFO" "$dest/packaging/millennium-helpers/"
  cp "${REPO_ROOT}/packaging/millennium-helpers/millennium-helpers.sudoers" "$dest/packaging/millennium-helpers/"
  cp "${REPO_ROOT}/packaging/millennium-helpers/millennium-helpers.install" "$dest/packaging/millennium-helpers/"
  cp "${REPO_ROOT}/nix/release-info.nix" "$dest/nix/"
  cp "${REPO_ROOT}/pyproject.toml" "$dest/"
  cp "${REPO_ROOT}/VERSION" "$dest/"
}

# Rewrite version strings/URLs to $ver while leaving checksums alone.
seed_version_only() {
  local dest="$1" ver="$2"
  printf '%s\n' "$ver" > "$dest/VERSION"
  python3 - "$dest" "$ver" <<'PY'
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
ver = sys.argv[2]

def rewrite_urls(text: str) -> str:
    return re.sub(r"/v[^/]+/", f"/v{ver}/", text)

(root / "pyproject.toml").write_text(
    re.sub(r'(?m)^version\s*=\s*"[^"]+"', f'version = "{ver}"', (root / "pyproject.toml").read_text(), count=1)
)
formula = root / "Formula/millennium-helpers.rb"
formula.write_text(rewrite_urls(formula.read_text()))
pkg = root / "packaging/millennium-helpers/PKGBUILD"
pkg.write_text(
    re.sub(r"(?m)^pkgver=.*$", f"pkgver={ver}", pkg.read_text(), count=1)
)
src = root / "packaging/millennium-helpers/.SRCINFO"
info = src.read_text()
info = re.sub(r"(?m)^(\tpkgver = ).*$", rf"\g<1>{ver}", info, count=1)
info = rewrite_urls(info)
src.write_text(info)
scoop_path = root / "packaging/scoop/millennium-helpers.json"
scoop = json.loads(scoop_path.read_text())
scoop["version"] = ver
scoop["url"] = rewrite_urls(str(scoop.get("url", "")))
scoop_path.write_text(json.dumps(scoop, indent=4) + "\n")
for rel in (
    "packaging/winget/bolens.millenniumhelpers.yaml",
    "packaging/winget/bolens.millenniumhelpers.installer.yaml",
    "packaging/winget/bolens.millenniumhelpers.locale.en-US.yaml",
):
    p = root / rel
    text = rewrite_urls(p.read_text())
    text = re.sub(r"(?m)^PackageVersion:\s*.*$", f"PackageVersion: {ver}", text, count=1)
    p.write_text(text)
ri = root / "nix/release-info.nix"
ri.write_text(re.sub(r'version = "[^"]+"', f'version = "{ver}"', ri.read_text(), count=1))
PY
}

echo -e "${YELLOW}=== Behavioral tests: packaging CI helpers ===${NC}"

# --- Argument validation ---

out=$(bash "$UPDATE" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh without args exits non-zero"

out=$(bash "$UPDATE" "not-a-version" \
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh rejects invalid version"
assert_contains "$out" "invalid version" "update-packaging-versions.sh explains invalid version"

out=$(bash "$UPDATE" "9.9.9" "deadbeef" \
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh rejects short linux sha"
assert_contains "$out" "sha256" "update-packaging-versions.sh mentions sha256 on short hash"

ZERO="0000000000000000000000000000000000000000000000000000000000000000"
GOOD="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
out=$(bash "$UPDATE" "9.9.9" "$ZERO" "$GOOD" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh rejects all-zero linux sha"
assert_contains "$out" "placeholder" "update-packaging-versions.sh explains placeholder refusal"

out=$(bash "$UPDATE" "9.9.9" "$GOOD" "$ZERO" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh rejects all-zero windows sha"

out=$(bash "$BUMP" 2>&1); rc=$?
assert_failure "$rc" "bump-version.sh without args exits non-zero"

out=$(bash "$BUMP" "not-a-version" 2>&1); rc=$?
assert_failure "$rc" "bump-version.sh rejects invalid version"
assert_contains "$out" "invalid version" "bump-version.sh explains invalid version"

out=$(bash "$SYNC_SRC" --bogus 2>&1); rc=$?
assert_exit_code 2 "$rc" "sync-stable-srcinfo.sh rejects unknown args"
assert_contains "$out" "usage:" "sync-stable-srcinfo.sh prints usage on bad args"

# --- Successful update writes quoted Winget hash and verifies round-trip ---

WORK=$(mktemp -d)
SYNC_WORK=$(mktemp -d)
BUMP_WORK=$(mktemp -d)
CHECK_WORK=$(mktemp -d)
# shellcheck disable=SC2064
trap 'rm -rf "$WORK" "$SYNC_WORK" "$BUMP_WORK" "$CHECK_WORK"' EXIT

seed_packaging_tree "$WORK"
echo "0.0.0" > "$WORK/VERSION"

LINUX_SHA="1111111111111111111111111111111111111111111111111111111111111111"
WINDOWS_SHA="2222222222222222222222222222222222222222222222222222222222222222"

out=$(
  cd "$WORK" && bash scripts/ci/update-packaging-versions.sh \
    "3.4.5" "$LINUX_SHA" "$WINDOWS_SHA" 2>&1
)
rc=$?
assert_success "$rc" "update-packaging-versions.sh succeeds with valid hashes"
assert_contains "$out" "Verified packaging hashes" "update-packaging-versions.sh verifies written hashes"
assert_equals "3.4.5" "$(tr -d '[:space:]' < "$WORK/VERSION")" "VERSION file updated"

formula=$(cat "$WORK/Formula/millennium-helpers.rb")
assert_contains "$formula" "sha256 \"${LINUX_SHA}\"" "Formula receives lowercase linux sha256"
assert_contains "$formula" "releases/download/v3.4.5/millennium-helpers-linux.tar.gz" "Formula URL points at trimmed Linux release asset"
assert_contains "$formula" 'license "MIT"' "Formula declares MIT license"
assert_not_contains "$formula" 'version "3.4.5"' "Formula has no redundant version line after packaging update"

scoop=$(cat "$WORK/packaging/scoop/millennium-helpers.json")
assert_contains "$scoop" "\"hash\": \"${WINDOWS_SHA}\"" "Scoop receives windows sha256"
assert_contains "$scoop" "releases/download/v3.4.5/millennium-helpers-windows.zip" "Scoop URL points at trimmed Windows release asset"
assert_contains "$scoop" "millennium-helpers-windows.zip.sha256" "Scoop autoupdate hash uses .sha256 sidecar"

winget=$(cat "$WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml")
WINDOWS_SHA_UC="$(printf '%s' "$WINDOWS_SHA" | tr '[:lower:]' '[:upper:]')"
assert_contains "$winget" "InstallerSha256: \"${WINDOWS_SHA_UC}\"" "Winget InstallerSha256 is quoted uppercase"
assert_contains "$winget" "releases/download/v3.4.5/millennium-helpers-windows.zip" "Winget InstallerUrl points at trimmed Windows release asset"
assert_contains "$winget" "PackageVersion: 3.4.5" "Winget installer PackageVersion updated"
assert_contains "$winget" "InstallerType: zip" "Winget installer uses zip (no portable .ps1 claims)"
assert_not_contains "$winget" "NestedInstallerFiles" "Winget installer has no NestedInstallerFiles"
assert_not_contains "$winget" "PortableCommandAliases" "Winget installer has no PortableCommandAliases"

aur=$(cat "$WORK/packaging/millennium-helpers/PKGBUILD")
assert_contains "$aur" "pkgver=3.4.5" "Arch versioned PKGBUILD pkgver updated"
assert_contains "$aur" "${LINUX_SHA}" "Arch versioned PKGBUILD receives linux sha256"
aur_srcinfo=$(cat "$WORK/packaging/millennium-helpers/.SRCINFO")
assert_contains "$aur_srcinfo" "pkgver = 3.4.5" "Arch versioned .SRCINFO pkgver updated"
assert_contains "$aur_srcinfo" "releases/download/v3.4.5/millennium-helpers-linux.tar.gz" "Arch .SRCINFO source URL expanded to new version"
assert_contains "$aur_srcinfo" "sha256sums = ${LINUX_SHA}" "Arch .SRCINFO tarball sha synced via sync-stable-srcinfo"
nix_info=$(cat "$WORK/nix/release-info.nix")
assert_contains "$nix_info" 'version = "3.4.5"' "Nix release-info.nix version updated"
assert_contains "$nix_info" "sha256-" "Nix release-info.nix has SRI srcHash"

# --- sync-stable-srcinfo.sh: check + write + PRE_COMMIT abort ---

seed_packaging_tree "$SYNC_WORK"
seed_version_only "$SYNC_WORK" "1.2.3"
# Align .SRCINFO with PKGBUILD first.
(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh) >/dev/null
out=$(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh --check 2>&1); rc=$?
assert_success "$rc" "sync-stable-srcinfo --check passes when .SRCINFO matches PKGBUILD"
assert_contains "$out" "stable .SRCINFO OK" "sync-stable-srcinfo --check reports OK"

# Stale source URL (the v2.5.0 CI failure mode).
sed_inplace 's|releases/download/v1.2.3/|releases/download/v0.9.9/|' \
  "$SYNC_WORK/packaging/millennium-helpers/.SRCINFO"
out=$(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh --check 2>&1); rc=$?
assert_failure "$rc" "sync-stable-srcinfo --check fails on stale source URL"
assert_contains "$out" "out of date" "sync-stable-srcinfo --check explains stale .SRCINFO"

out=$(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh 2>&1); rc=$?
assert_success "$rc" "sync-stable-srcinfo write mode repairs stale .SRCINFO"
assert_contains "$(cat "$SYNC_WORK/packaging/millennium-helpers/.SRCINFO")" \
  "releases/download/v1.2.3/millennium-helpers-linux.tar.gz" \
  "sync-stable-srcinfo write restores expanded source URL"

# Stale pkgver line.
sed_inplace 's/\tpkgver = .*/\tpkgver = 0.0.1/' "$SYNC_WORK/packaging/millennium-helpers/.SRCINFO"
out=$(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh --check 2>&1); rc=$?
assert_failure "$rc" "sync-stable-srcinfo --check fails on stale pkgver"

# Stale tarball sha256sums (first sha256sums line only; portable across GNU/BSD sed).
(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh) >/dev/null
python3 - "$SYNC_WORK/packaging/millennium-helpers/.SRCINFO" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text2, n = re.subn(
    r"(?m)^(\tsha256sums = )[0-9a-fA-F]{64}$",
    r"\g<1>aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    text,
    count=1,
)
if n != 1:
    raise SystemExit(f"expected one sha256sums line to rewrite, got {n}")
path.write_text(text2, encoding="utf-8")
PY
out=$(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh --check 2>&1); rc=$?
assert_failure "$rc" "sync-stable-srcinfo --check fails on stale tarball sha256"

# PRE_COMMIT abort when write changes files.
sed_inplace 's|releases/download/v1.2.3/|releases/download/v0.1.0/|' \
  "$SYNC_WORK/packaging/millennium-helpers/.SRCINFO"
out=$(cd "$SYNC_WORK" && PRE_COMMIT=1 bash scripts/ci/sync-stable-srcinfo.sh 2>&1); rc=$?
assert_failure "$rc" "sync-stable-srcinfo under PRE_COMMIT exits non-zero after rewrite"
assert_contains "$out" "re-stage" "sync-stable-srcinfo under PRE_COMMIT asks to re-stage"

# --- bump-version.sh (pre-tag): versions/URLs move, hashes stay ---

seed_packaging_tree "$BUMP_WORK"
seed_version_only "$BUMP_WORK" "1.0.0"
# Capture hashes before bump.
FORMULA_SHA_BEFORE="$(grep -E '^\s*sha256\s+"' "$BUMP_WORK/Formula/millennium-helpers.rb" | head -1)"
SCOOP_HASH_BEFORE="$(python3 -c "import json; print(json.load(open('$BUMP_WORK/packaging/scoop/millennium-helpers.json'))['hash'])")"
WINGET_SHA_BEFORE="$(grep -E '^\s*InstallerSha256:' "$BUMP_WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml" | head -1)"
PKG_SHA_BEFORE="$(grep -E "^sha256sums=\('" "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD" | head -1)"
NIX_HASH_BEFORE="$(grep -E '^\s*srcHash\s*=' "$BUMP_WORK/nix/release-info.nix" | head -1)"
# Deliberately stale .SRCINFO source URL before bump.
sed_inplace 's|releases/download/v1.0.0/|releases/download/v0.9.9/|' \
  "$BUMP_WORK/packaging/millennium-helpers/.SRCINFO"
# Bump pkgrel so we can assert reset.
sed_inplace 's/^pkgrel=.*/pkgrel=7/' "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD"

out=$(cd "$BUMP_WORK" && bash scripts/ci/bump-version.sh "v9.8.7" 2>&1); rc=$?
assert_success "$rc" "bump-version.sh succeeds (strips leading v)"
assert_equals "9.8.7" "$(tr -d '[:space:]' < "$BUMP_WORK/VERSION")" "bump-version updates VERSION"
assert_contains "$(cat "$BUMP_WORK/pyproject.toml")" 'version = "9.8.7"' "bump-version updates pyproject.toml"
assert_contains "$(cat "$BUMP_WORK/Formula/millennium-helpers.rb")" \
  "releases/download/v9.8.7/millennium-helpers-linux.tar.gz" "bump-version updates Formula URL"
assert_contains "$(cat "$BUMP_WORK/packaging/scoop/millennium-helpers.json")" \
  '"version": "9.8.7"' "bump-version updates Scoop version"
assert_contains "$(cat "$BUMP_WORK/packaging/scoop/millennium-helpers.json")" \
  "releases/download/v9.8.7/millennium-helpers-windows.zip" "bump-version updates Scoop URL"
assert_contains "$(cat "$BUMP_WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml")" \
  "PackageVersion: 9.8.7" "bump-version updates Winget installer PackageVersion"
assert_contains "$(cat "$BUMP_WORK/packaging/winget/bolens.millenniumhelpers.yaml")" \
  "PackageVersion: 9.8.7" "bump-version updates Winget default PackageVersion"
assert_contains "$(cat "$BUMP_WORK/packaging/winget/bolens.millenniumhelpers.locale.en-US.yaml")" \
  "PackageVersion: 9.8.7" "bump-version updates Winget locale PackageVersion"
assert_contains "$(cat "$BUMP_WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml")" \
  "releases/download/v9.8.7/millennium-helpers-windows.zip" "bump-version updates Winget InstallerUrl"
assert_contains "$(cat "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD")" "pkgver=9.8.7" \
  "bump-version updates Arch PKGBUILD pkgver"
assert_contains "$(cat "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD")" "pkgrel=1" \
  "bump-version resets Arch PKGBUILD pkgrel to 1"
assert_contains "$(cat "$BUMP_WORK/packaging/millennium-helpers/.SRCINFO")" \
  "releases/download/v9.8.7/millennium-helpers-linux.tar.gz" \
  "bump-version regenerates .SRCINFO source URL (not left on old tag)"
assert_contains "$(cat "$BUMP_WORK/nix/release-info.nix")" 'version = "9.8.7"' \
  "bump-version updates nix/release-info.nix version"
assert_contains "$out" "All packaging versions match VERSION" "bump-version runs check-version-sync"

FORMULA_SHA_AFTER="$(grep -E '^\s*sha256\s+"' "$BUMP_WORK/Formula/millennium-helpers.rb" | head -1)"
SCOOP_HASH_AFTER="$(python3 -c "import json; print(json.load(open('$BUMP_WORK/packaging/scoop/millennium-helpers.json'))['hash'])")"
WINGET_SHA_AFTER="$(grep -E '^\s*InstallerSha256:' "$BUMP_WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml" | head -1)"
PKG_SHA_AFTER="$(grep -E "^sha256sums=\('" "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD" | head -1)"
NIX_HASH_AFTER="$(grep -E '^\s*srcHash\s*=' "$BUMP_WORK/nix/release-info.nix" | head -1)"
assert_equals "$FORMULA_SHA_BEFORE" "$FORMULA_SHA_AFTER" "bump-version preserves Formula sha256"
assert_equals "$SCOOP_HASH_BEFORE" "$SCOOP_HASH_AFTER" "bump-version preserves Scoop hash"
assert_equals "$WINGET_SHA_BEFORE" "$WINGET_SHA_AFTER" "bump-version preserves Winget InstallerSha256"
assert_equals "$PKG_SHA_BEFORE" "$PKG_SHA_AFTER" "bump-version preserves Arch PKGBUILD sha256sums"
assert_equals "$NIX_HASH_BEFORE" "$NIX_HASH_AFTER" "bump-version preserves nix srcHash"

# --- check-version-sync.sh: new pyproject + .SRCINFO guards ---

seed_packaging_tree "$CHECK_WORK"
seed_version_only "$CHECK_WORK" "4.5.6"
(cd "$CHECK_WORK" && bash scripts/ci/sync-stable-srcinfo.sh) >/dev/null
out=$(cd "$CHECK_WORK" && bash scripts/ci/check-version-sync.sh 2>&1); rc=$?
assert_success "$rc" "check-version-sync passes on seeded consistent tree"
assert_contains "$out" "pyproject.toml version OK" "check-version-sync validates pyproject.toml"
assert_contains "$out" ".SRCINFO OK" "check-version-sync validates stable .SRCINFO"

sed_inplace 's/^version = .*/version = "0.0.0"/' "$CHECK_WORK/pyproject.toml"
out=$(cd "$CHECK_WORK" && bash scripts/ci/check-version-sync.sh 2>&1); rc=$?
assert_failure "$rc" "check-version-sync fails when pyproject.toml mismatches VERSION"
assert_contains "$out" "pyproject.toml" "check-version-sync names pyproject.toml on mismatch"
sed_inplace 's/^version = .*/version = "4.5.6"/' "$CHECK_WORK/pyproject.toml"

sed_inplace 's|releases/download/v4.5.6/|releases/download/v4.5.5/|' \
  "$CHECK_WORK/packaging/millennium-helpers/.SRCINFO"
out=$(cd "$CHECK_WORK" && bash scripts/ci/check-version-sync.sh 2>&1); rc=$?
assert_failure "$rc" "check-version-sync fails when stable .SRCINFO source URL is stale"
assert_contains "$out" ".SRCINFO" "check-version-sync mentions .SRCINFO on drift"

# --- check-winget-manifests accepts quoted placeholder on main ---

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  out=$(bash "$WINGET_CHECK" 2>&1)
  rc=$?
  assert_success "$rc" "check-winget-manifests.sh passes on current manifests"
  assert_contains "$out" "passed" "check-winget-manifests.sh reports success"
else
  echo -e "${YELLOW}SKIP:${NC} check-winget-manifests.sh (PyYAML not installed)"
fi

# --- release.yml Windows zip must ship the shared MCP Python server ---
windows_zip_block=$(awk '/Create Windows Release Zip/,/Calculate Checksums/' "${REPO_ROOT}/.github/workflows/release.yml")
assert_contains "$windows_zip_block" "scripts/millennium-mcp.py" "Windows release zip includes millennium-mcp.py"
assert_contains "$windows_zip_block" "completions/powershell/" "Windows release zip includes PowerShell completions"
assert_contains "$windows_zip_block" "scripts/windows/" "Windows release zip includes scripts/windows tree (diag lib modules)"
assert_contains "$windows_zip_block" "millennium-helpers-windows.zip" "release.yml builds trimmed Windows zip"

# Modular Windows diag lives under scripts/windows/lib — ensure the tree is shipped.
assert_file_exists "${REPO_ROOT}/scripts/windows/lib/Diag.ps1" "scripts/windows/lib/Diag.ps1 exists for release packaging"
assert_file_exists "${REPO_ROOT}/scripts/windows/lib/DiagInstall.ps1" "scripts/windows/lib/DiagInstall.ps1 exists for release packaging"
assert_file_exists "${REPO_ROOT}/scripts/windows/lib/DiagDoctor.ps1" "scripts/windows/lib/DiagDoctor.ps1 exists for release packaging"

# Release CD gate must wait on ShellCheck + completions, not only the test suite
release_gate=$(awk '/name: Wait for required CI/,/build-release:/' "${REPO_ROOT}/.github/workflows/release.yml")
assert_contains "$release_gate" "test-suite.yml" "release gate waits on test-suite.yml"
assert_contains "$release_gate" "shellcheck.yml" "release gate waits on shellcheck.yml"
assert_contains "$release_gate" "completions.yml" "release gate waits on completions.yml"

# --- Workflow path-filter sanity (avoid docs-only / LICENSE over-triggers) ---
scoop_ci=$(cat "${REPO_ROOT}/.github/workflows/package-install-windows.yml")
assert_contains "$scoop_ci" "millennium-mcp.py" "Scoop CI stages millennium-mcp.py beside scripts/windows"
assert_contains "$scoop_ci" "completions\\powershell" "Scoop CI stages PowerShell completions in the trimmed zip"
assert_not_contains "$scoop_ci" "- 'README.md'" "Scoop CI path filters do not trigger on README-only docs edits"
assert_not_contains "$scoop_ci" "- 'LICENSE'" "Scoop CI path filters do not trigger on LICENSE-only edits"

nix_wf=$(cat "${REPO_ROOT}/.github/workflows/nix.yml")
assert_contains "$nix_wf" "- 'VERSION'" "Nix CI path filters include VERSION"
assert_not_contains "$nix_wf" "- 'LICENSE'" "Nix CI path filters do not trigger on LICENSE-only edits"
assert_contains "$nix_wf" "Release asset not published yet" "Nix CI skips unpublished release tarball builds"
assert_contains "$nix_wf" "millennium-helpers-git" "Nix CI always builds git package"

pkg_wf=$(cat "${REPO_ROOT}/.github/workflows/pkgbuild.yml")
assert_contains "$pkg_wf" "- 'VERSION'" "PKGBUILD CI path filters include VERSION"
assert_contains "$pkg_wf" "millennium-helpers-git" "PKGBUILD CI validates -git package"
assert_contains "$pkg_wf" "packaging/millennium-helpers/**" "PKGBUILD CI path filters include versioned package"
assert_not_contains "$pkg_wf" "- 'LICENSE'" "PKGBUILD CI path filters do not trigger on LICENSE-only edits"
assert_contains "$pkg_wf" "Release asset not published yet" "PKGBUILD CI skips unpublished release tarball builds"
assert_contains "$pkg_wf" "curl" "PKGBUILD CI installs curl for release-asset probe"

suite_wf=$(cat "${REPO_ROOT}/.github/workflows/test-suite.yml")
assert_contains "$suite_wf" "- 'man/**'" "Test suite path filters include man pages"
assert_contains "$suite_wf" "- 'Formula/**'" "Test suite path filters include Formula"
assert_contains "$suite_wf" "- 'packaging/**'" "Test suite path filters include all packaging manifests"
assert_contains "$suite_wf" "- '.github/workflows/release.yml'" "Test suite path filters include release.yml"

ps_lint=$(cat "${REPO_ROOT}/.github/workflows/powershell-lint.yml")
assert_contains "$ps_lint" "completions/powershell" "PowerShell lint path filters include completions/powershell"

# Remaining packaging CIs: no docs/LICENSE over-triggers; VERSION where the package embeds it
for wf in homebrew.yml package-manifests.yml version-sync.yml man-pages.yml python-lint.yml; do
  body=$(cat "${REPO_ROOT}/.github/workflows/${wf}")
  assert_not_contains "$body" "- 'LICENSE'" "${wf} path filters do not trigger on LICENSE-only edits"
  assert_not_contains "$body" "- 'README.md'" "${wf} path filters do not trigger on README-only docs edits"
done

hb=$(cat "${REPO_ROOT}/.github/workflows/homebrew.yml")
assert_contains "$hb" "- 'Formula/**'" "Homebrew CI path filters include Formula"

vs=$(cat "${REPO_ROOT}/.github/workflows/version-sync.yml")
assert_contains "$vs" "- 'VERSION'" "version-sync path filters include VERSION"
assert_contains "$vs" "- 'Formula/**'" "version-sync path filters include Formula"
assert_contains "$vs" "- 'pyproject.toml'" "version-sync path filters include pyproject.toml"
assert_contains "$vs" "sync-stable-srcinfo.sh" "version-sync path filters include sync-stable-srcinfo.sh"
assert_contains "$vs" "bump-version.sh" "version-sync path filters include bump-version.sh"

pre_commit=$(cat "${REPO_ROOT}/.pre-commit-config.yaml")
assert_contains "$pre_commit" "sync-stable-srcinfo" "pre-commit includes sync-stable-srcinfo hook"
assert_contains "$pre_commit" "packaging/millennium-helpers" "pre-commit version-sync watches Arch packaging"

makefile=$(cat "${REPO_ROOT}/Makefile")
assert_contains "$makefile" "bump-version" "Makefile exposes bump-version target"
assert_contains "$makefile" "sync-stable-srcinfo" "Makefile exposes sync-stable-srcinfo target"
# Intentional literal $(VERSION) — Makefile forwards the make variable.
# shellcheck disable=SC2016
assert_contains "$makefile" 'bump-version.sh "$(VERSION)"' "Makefile bump-version forwards VERSION"

print_summary
