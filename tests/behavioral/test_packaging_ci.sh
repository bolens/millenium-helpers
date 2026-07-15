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
SYNC_BIN="${REPO_ROOT}/scripts/ci/sync-bin-srcinfo.sh"
PACK_CHECK="${REPO_ROOT}/scripts/ci/check-packaging-manifests.sh"
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
    "$dest/packaging/millennium-helpers" "$dest/packaging/millennium-helpers-bin" \
    "$dest/packaging/deb/millennium-helpers/DEBIAN" \
    "$dest/packaging/deb/millennium-helpers-bin/DEBIAN" \
    "$dest/packaging/rpm" \
    "$dest/packaging/chocolatey/millennium-helpers/tools" \
    "$dest/nix" "$dest/scripts/ci"
  cp "$UPDATE" "$BUMP" "$CHECK" "$SYNC_SRC" "$SYNC_BIN" "$dest/scripts/ci/"
  cp "${REPO_ROOT}/scripts/ci/release_assets.sh" "$dest/scripts/ci/"
  cp "${REPO_ROOT}/Formula/millennium-helpers.rb" "$dest/Formula/"
  cp "${REPO_ROOT}/Formula/millennium-helpers-bin.rb" "$dest/Formula/"
  cp "${REPO_ROOT}/packaging/scoop/"*.json "$dest/packaging/scoop/"
  cp "${REPO_ROOT}/packaging/winget/"*.yaml "$dest/packaging/winget/"
  cp "${REPO_ROOT}/packaging/millennium-helpers/PKGBUILD" "$dest/packaging/millennium-helpers/"
  cp "${REPO_ROOT}/packaging/millennium-helpers/.SRCINFO" "$dest/packaging/millennium-helpers/"
  cp "${REPO_ROOT}/packaging/millennium-helpers/millennium-helpers.sudoers" "$dest/packaging/millennium-helpers/"
  cp "${REPO_ROOT}/packaging/millennium-helpers/millennium-helpers.install" "$dest/packaging/millennium-helpers/"
  cp "${REPO_ROOT}/packaging/millennium-helpers-bin/PKGBUILD" "$dest/packaging/millennium-helpers-bin/"
  cp "${REPO_ROOT}/packaging/millennium-helpers-bin/.SRCINFO" "$dest/packaging/millennium-helpers-bin/"
  cp "${REPO_ROOT}/packaging/millennium-helpers-bin/millennium-helpers.sudoers" "$dest/packaging/millennium-helpers-bin/"
  cp "${REPO_ROOT}/packaging/millennium-helpers-bin/millennium-helpers.install" "$dest/packaging/millennium-helpers-bin/"
  cp "${REPO_ROOT}/packaging/deb/millennium-helpers/DEBIAN/control" "$dest/packaging/deb/millennium-helpers/DEBIAN/"
  cp "${REPO_ROOT}/packaging/deb/millennium-helpers-bin/DEBIAN/control" "$dest/packaging/deb/millennium-helpers-bin/DEBIAN/"
  cp "${REPO_ROOT}/packaging/rpm/"*.spec "$dest/packaging/rpm/"
  cp "${REPO_ROOT}/packaging/chocolatey/millennium-helpers/millennium-helpers.nuspec" \
    "$dest/packaging/chocolatey/millennium-helpers/"
  cp "${REPO_ROOT}/packaging/chocolatey/millennium-helpers/tools/"*.ps1 \
    "$dest/packaging/chocolatey/millennium-helpers/tools/"
  cp "${REPO_ROOT}/nix/release-info.nix" "$dest/nix/"
  cp "${REPO_ROOT}/pyproject.toml" "$dest/"
  cp "${REPO_ROOT}/VERSION" "$dest/"
}

# Rewrite version strings/URLs to $ver while leaving checksums alone.
seed_version_only() {
  local dest="$1" ver="$2"
  [[ -n "$dest" && "$dest" != "." && "$dest" != "/" ]] || {
    echo "error: seed_version_only requires an absolute temp dest" >&2
    return 1
  }
  printf '%s\n' "$ver" > "$dest/VERSION"
  python3 - "$dest" "$ver" <<'PY'
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
ver = sys.argv[2]
if root in (Path("/"), Path(".").resolve()) or str(root) == "":
    raise SystemExit("refusing to seed version into repo root / cwd")

repo = "bolens/millenium-helpers"

def bump_release_url(text: str) -> str:
    text = re.sub(r"/releases/download/v[^/]+/", f"/releases/download/v{ver}/", text)
    text = re.sub(
        r"(millennium-helpers-v)[0-9][^/\"'\s-]*(-)",
        rf"\g<1>{ver}\g<2>",
        text,
    )
    return text

# Formula: replace only the first stable url= line (never touch head).
src_formula = root / "Formula/millennium-helpers.rb"
text = src_formula.read_text(encoding="utf-8")
text = re.sub(
    r'(?m)^(  url\s+")https://github\.com/[^"]+(")',
    rf'\g<1>https://github.com/{repo}/releases/download/v{ver}/millennium-helpers-v{ver}-src.tar.gz\g<2>',
    text,
    count=1,
)
src_formula.write_text(text, encoding="utf-8")

bin_formula = root / "Formula/millennium-helpers-bin.rb"
text = bin_formula.read_text(encoding="utf-8")
# Rewrite version segment in all release download URLs for Formula-bin
text = re.sub(
    r'(releases/download/)v[^/]+(/millennium-helpers-v)[^/-]+(-)',
    rf'\g<1>v{ver}\g<2>{ver}\g<3>',
    text,
)
bin_formula.write_text(text, encoding="utf-8")

(root / "pyproject.toml").write_text(
    re.sub(r'(?m)^version\s*=\s*"[^"]+"', f'version = "{ver}"', (root / "pyproject.toml").read_text(), count=1)
)

for pkg, tag_src in (
    ("millennium-helpers", True),
    ("millennium-helpers-bin", False),
):
    pkgb = root / f"packaging/{pkg}/PKGBUILD"
    pkgb.write_text(re.sub(r"(?m)^pkgver=.*$", f"pkgver={ver}", pkgb.read_text(), count=1))
    src = root / f"packaging/{pkg}/.SRCINFO"
    info = src.read_text(encoding="utf-8")
    info = re.sub(r"(?m)^(\tpkgver = ).*$", rf"\g<1>{ver}", info, count=1)
    if tag_src:
        info = re.sub(
            r"(?m)^(\tsource = https://github\.com/.+/releases/download/)v[^/\n]+(/millennium-helpers-v)[^/\n]+(-src\.tar\.gz)$",
            rf"\g<1>v{ver}\g<2>{ver}\g<3>",
            info,
            count=1,
        )
    else:
        info = bump_release_url(info)
    src.write_text(info, encoding="utf-8")

scoop_src = root / "packaging/scoop/millennium-helpers.json"
data = json.loads(scoop_src.read_text(encoding="utf-8"))
data["version"] = ver
data["url"] = f"https://github.com/{repo}/releases/download/v{ver}/millennium-helpers-v{ver}-src.zip"
data["extract_dir"] = f"millenium-helpers-{ver}"
if isinstance(data.get("autoupdate"), dict):
    data["autoupdate"]["url"] = f"https://github.com/{repo}/releases/download/v$version/millennium-helpers-v$version-src.zip"
    data["autoupdate"]["extract_dir"] = "millenium-helpers-$version"
scoop_src.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")

scoop_bin = root / "packaging/scoop/millennium-helpers-bin.json"
data = json.loads(scoop_bin.read_text(encoding="utf-8"))
data["version"] = ver
data["url"] = f"https://github.com/{repo}/releases/download/v{ver}/millennium-helpers-v{ver}-windows-amd64.zip"
scoop_bin.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")

for rel in (
    "packaging/winget/bolens.millenniumhelpers.yaml",
    "packaging/winget/bolens.millenniumhelpers.installer.yaml",
    "packaging/winget/bolens.millenniumhelpers.locale.en-US.yaml",
):
    p = root / rel
    text = bump_release_url(p.read_text(encoding="utf-8"))
    text = re.sub(r"(?m)^PackageVersion:\s*.*$", f"PackageVersion: {ver}", text, count=1)
    p.write_text(text, encoding="utf-8")

for ctrl in (
    "packaging/deb/millennium-helpers/DEBIAN/control",
    "packaging/deb/millennium-helpers-bin/DEBIAN/control",
):
    p = root / ctrl
    p.write_text(re.sub(r"(?m)^Version:\s*.*$", f"Version: {ver}", p.read_text(), count=1))

for spec in (
    "packaging/rpm/millennium-helpers.spec",
    "packaging/rpm/millennium-helpers-bin.spec",
):
    p = root / spec
    p.write_text(re.sub(r"(?m)^Version:\s*.*$", f"Version: {ver}", p.read_text(), count=1))

nuspec = root / "packaging/chocolatey/millennium-helpers/millennium-helpers.nuspec"
nuspec.write_text(re.sub(r"<version>[^<]+</version>", f"<version>{ver}</version>", nuspec.read_text(), count=1))
choco = root / "packaging/chocolatey/millennium-helpers/tools/chocolateyInstall.ps1"
choco.write_text(re.sub(r"(\$version\s*=\s*')[^']+(')", rf"\g<1>{ver}\g<2>", choco.read_text(), count=1))

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

# --- Successful update writes from-source + bin hashes ---

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
TAG_TAR_SHA="3333333333333333333333333333333333333333333333333333333333333333"
TAG_ZIP_SHA="4444444444444444444444444444444444444444444444444444444444444444"

out=$(
  cd "$WORK" && bash scripts/ci/update-packaging-versions.sh \
    "3.4.5" "$LINUX_SHA" "$WINDOWS_SHA" "bolens/millenium-helpers" \
    "$TAG_TAR_SHA" "$TAG_ZIP_SHA" 2>&1
)
rc=$?
assert_success "$rc" "update-packaging-versions.sh succeeds with valid hashes"
assert_contains "$out" "Verified packaging hashes" "update-packaging-versions.sh verifies written hashes"
assert_equals "3.4.5" "$(tr -d '[:space:]' < "$WORK/VERSION")" "VERSION file updated"

formula=$(cat "$WORK/Formula/millennium-helpers.rb")
assert_contains "$formula" "sha256 \"${TAG_TAR_SHA}\"" "from-source Formula receives tag archive sha256"
assert_contains "$formula" "releases/download/v3.4.5/millennium-helpers-v3.4.5-src.tar.gz" "from-source Formula URL points at tag archive"
assert_contains "$formula" 'license "MIT"' "Formula declares MIT license"
assert_not_contains "$formula" 'version "3.4.5"' "Formula has no redundant version line after packaging update"

formula_bin=$(cat "$WORK/Formula/millennium-helpers-bin.rb")
assert_contains "$formula_bin" "sha256 \"${LINUX_SHA}\"" "bin Formula receives linux sha256"
assert_contains "$formula_bin" "releases/download/v3.4.5/millennium-helpers-v3.4.5-linux-amd64.tar.gz" "bin Formula URL points at release tarball"

scoop=$(cat "$WORK/packaging/scoop/millennium-helpers.json")
assert_contains "$scoop" "\"hash\": \"${TAG_ZIP_SHA}\"" "Scoop from-source receives tag zip sha256"
assert_contains "$scoop" "releases/download/v3.4.5/millennium-helpers-v3.4.5-src.zip" "Scoop from-source URL points at tag zip"

scoop_bin=$(cat "$WORK/packaging/scoop/millennium-helpers-bin.json")
assert_contains "$scoop_bin" "\"hash\": \"${WINDOWS_SHA}\"" "Scoop-bin receives windows sha256"
assert_contains "$scoop_bin" "releases/download/v3.4.5/millennium-helpers-v3.4.5-windows-amd64.zip" "Scoop-bin URL points at Windows release zip"
assert_contains "$scoop_bin" "millennium-helpers-v\$version-windows-amd64.zip.sha256" "Scoop-bin autoupdate hash uses .sha256 sidecar"

winget=$(cat "$WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml")
WINDOWS_SHA_UC="$(printf '%s' "$WINDOWS_SHA" | tr '[:lower:]' '[:upper:]')"
assert_contains "$winget" "InstallerSha256: \"${WINDOWS_SHA_UC}\"" "Winget InstallerSha256 is quoted uppercase"
assert_contains "$winget" "releases/download/v3.4.5/millennium-helpers-v3.4.5-windows-amd64.zip" "Winget InstallerUrl points at trimmed Windows release asset"
assert_contains "$winget" "PackageVersion: 3.4.5" "Winget installer PackageVersion updated"
assert_contains "$winget" "InstallerType: zip" "Winget installer uses zip (no portable .ps1 claims)"
assert_not_contains "$winget" "NestedInstallerFiles" "Winget installer has no NestedInstallerFiles"
assert_not_contains "$winget" "PortableCommandAliases" "Winget installer has no PortableCommandAliases"

aur=$(cat "$WORK/packaging/millennium-helpers/PKGBUILD")
assert_contains "$aur" "pkgver=3.4.5" "Arch from-source PKGBUILD pkgver updated"
assert_contains "$aur" "${TAG_TAR_SHA}" "Arch from-source PKGBUILD receives tag archive sha256"
aur_srcinfo=$(cat "$WORK/packaging/millennium-helpers/.SRCINFO")
assert_contains "$aur_srcinfo" "pkgver = 3.4.5" "Arch from-source .SRCINFO pkgver updated"
assert_contains "$aur_srcinfo" "releases/download/v3.4.5/millennium-helpers-v3.4.5-src.tar.gz" "Arch from-source .SRCINFO source URL expanded"
assert_contains "$aur_srcinfo" "sha256sums = ${TAG_TAR_SHA}" "Arch from-source .SRCINFO sha synced"

aur_bin=$(cat "$WORK/packaging/millennium-helpers-bin/PKGBUILD")
assert_contains "$aur_bin" "pkgver=3.4.5" "Arch -bin PKGBUILD pkgver updated"
assert_contains "$aur_bin" "${LINUX_SHA}" "Arch -bin PKGBUILD receives linux sha256"

nix_info=$(cat "$WORK/nix/release-info.nix")
assert_contains "$nix_info" 'version = "3.4.5"' "Nix release-info.nix version updated"
assert_contains "$nix_info" "srcAssetHash" "Nix release-info.nix has srcAssetHash"
assert_contains "$nix_info" "srcGitHash" "Nix release-info.nix has srcGitHash"

assert_contains "$(cat "$WORK/packaging/deb/millennium-helpers/DEBIAN/control")" "Version: 3.4.5" \
  "deb from-source Version updated"
assert_contains "$(cat "$WORK/packaging/chocolatey/millennium-helpers/millennium-helpers.nuspec")" \
  "<version>3.4.5</version>" "Chocolatey nuspec version updated"

# --- sync-stable-srcinfo.sh: check + write + PRE_COMMIT abort ---

seed_packaging_tree "$SYNC_WORK"
seed_version_only "$SYNC_WORK" "1.2.3"
(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh) >/dev/null
out=$(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh --check 2>&1); rc=$?
assert_success "$rc" "sync-stable-srcinfo --check passes when .SRCINFO matches PKGBUILD"
assert_contains "$out" "stable .SRCINFO OK" "sync-stable-srcinfo --check reports OK"

sed_inplace 's|millennium-helpers-v1.2.3-src.tar.gz|millennium-helpers-v0.9.9-src.tar.gz|' \
  "$SYNC_WORK/packaging/millennium-helpers/.SRCINFO"
out=$(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh --check 2>&1); rc=$?
assert_failure "$rc" "sync-stable-srcinfo --check fails on stale source URL"
assert_contains "$out" "out of date" "sync-stable-srcinfo --check explains stale .SRCINFO"

out=$(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh 2>&1); rc=$?
assert_success "$rc" "sync-stable-srcinfo write mode repairs stale .SRCINFO"
assert_contains "$(cat "$SYNC_WORK/packaging/millennium-helpers/.SRCINFO")" \
  "millennium-helpers-v1.2.3-src.tar.gz" \
  "sync-stable-srcinfo write restores tag archive source URL"

sed_inplace 's/\tpkgver = .*/\tpkgver = 0.0.1/' "$SYNC_WORK/packaging/millennium-helpers/.SRCINFO"
out=$(cd "$SYNC_WORK" && bash scripts/ci/sync-stable-srcinfo.sh --check 2>&1); rc=$?
assert_failure "$rc" "sync-stable-srcinfo --check fails on stale pkgver"

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

sed_inplace 's|millennium-helpers-v1.2.3-src.tar.gz|millennium-helpers-v0.1.0-src.tar.gz|' \
  "$SYNC_WORK/packaging/millennium-helpers/.SRCINFO"
out=$(cd "$SYNC_WORK" && PRE_COMMIT=1 bash scripts/ci/sync-stable-srcinfo.sh 2>&1); rc=$?
assert_failure "$rc" "sync-stable-srcinfo under PRE_COMMIT exits non-zero after rewrite"
assert_contains "$out" "re-stage" "sync-stable-srcinfo under PRE_COMMIT asks to re-stage"

# --- bump-version.sh (pre-tag): versions/URLs move, hashes stay ---

seed_packaging_tree "$BUMP_WORK"
seed_version_only "$BUMP_WORK" "1.0.0"
FORMULA_SHA_BEFORE="$(grep -E '^\s*sha256\s+"' "$BUMP_WORK/Formula/millennium-helpers.rb" | head -1)"
FORMULA_BIN_SHA_BEFORE="$(grep -E '^\s*sha256\s+"' "$BUMP_WORK/Formula/millennium-helpers-bin.rb" | head -1)"
SCOOP_HASH_BEFORE="$(python3 -c "import json; print(json.load(open('$BUMP_WORK/packaging/scoop/millennium-helpers.json'))['hash'])")"
SCOOP_BIN_HASH_BEFORE="$(python3 -c "import json; print(json.load(open('$BUMP_WORK/packaging/scoop/millennium-helpers-bin.json'))['hash'])")"
WINGET_SHA_BEFORE="$(grep -E '^\s*InstallerSha256:' "$BUMP_WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml" | head -1)"
PKG_SHA_BEFORE="$(grep -E "^sha256sums=\('" "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD" | head -1)"
NIX_HASH_BEFORE="$(grep -E '^\s*srcAssetHash\s*=' "$BUMP_WORK/nix/release-info.nix" | head -1)"
sed_inplace 's|millennium-helpers-v1.0.0-src.tar.gz|millennium-helpers-v0.9.9-src.tar.gz|' \
  "$BUMP_WORK/packaging/millennium-helpers/.SRCINFO"
sed_inplace 's/^pkgrel=.*/pkgrel=7/' "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD"

out=$(cd "$BUMP_WORK" && bash scripts/ci/bump-version.sh "v9.8.7" 2>&1); rc=$?
assert_success "$rc" "bump-version.sh succeeds (strips leading v)"
assert_equals "9.8.7" "$(tr -d '[:space:]' < "$BUMP_WORK/VERSION")" "bump-version updates VERSION"
assert_contains "$(cat "$BUMP_WORK/pyproject.toml")" 'version = "9.8.7"' "bump-version updates pyproject.toml"
assert_contains "$(cat "$BUMP_WORK/Formula/millennium-helpers.rb")" \
  "releases/download/v9.8.7/millennium-helpers-v9.8.7-src.tar.gz" "bump-version updates from-source Formula URL"
assert_contains "$(cat "$BUMP_WORK/Formula/millennium-helpers-bin.rb")" \
  "releases/download/v9.8.7/millennium-helpers-v9.8.7-linux-amd64.tar.gz" "bump-version updates bin Formula URL"
assert_contains "$(cat "$BUMP_WORK/packaging/scoop/millennium-helpers.json")" \
  '"version": "9.8.7"' "bump-version updates Scoop from-source version"
assert_contains "$(cat "$BUMP_WORK/packaging/scoop/millennium-helpers.json")" \
  "releases/download/v9.8.7/millennium-helpers-v9.8.7-src.zip" "bump-version updates Scoop from-source URL"
assert_contains "$(cat "$BUMP_WORK/packaging/scoop/millennium-helpers-bin.json")" \
  "releases/download/v9.8.7/millennium-helpers-v9.8.7-windows-amd64.zip" "bump-version updates Scoop-bin URL"
assert_contains "$(cat "$BUMP_WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml")" \
  "PackageVersion: 9.8.7" "bump-version updates Winget installer PackageVersion"
assert_contains "$(cat "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD")" "pkgver=9.8.7" \
  "bump-version updates Arch from-source PKGBUILD pkgver"
assert_contains "$(cat "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD")" "pkgrel=1" \
  "bump-version resets Arch PKGBUILD pkgrel to 1"
assert_contains "$(cat "$BUMP_WORK/packaging/millennium-helpers/.SRCINFO")" \
  "releases/download/v9.8.7/millennium-helpers-v9.8.7-src.tar.gz" \
  "bump-version regenerates from-source .SRCINFO source URL"
assert_contains "$(cat "$BUMP_WORK/packaging/millennium-helpers-bin/PKGBUILD")" "pkgver=9.8.7" \
  "bump-version updates Arch -bin PKGBUILD pkgver"
assert_contains "$(cat "$BUMP_WORK/nix/release-info.nix")" 'version = "9.8.7"' \
  "bump-version updates nix/release-info.nix version"
assert_contains "$(cat "$BUMP_WORK/packaging/deb/millennium-helpers/DEBIAN/control")" "Version: 9.8.7" \
  "bump-version updates deb Version"
assert_contains "$(cat "$BUMP_WORK/packaging/chocolatey/millennium-helpers/millennium-helpers.nuspec")" \
  "<version>9.8.7</version>" "bump-version updates Chocolatey version"
assert_contains "$out" "All packaging versions match VERSION" "bump-version runs check-version-sync"

FORMULA_SHA_AFTER="$(grep -E '^\s*sha256\s+"' "$BUMP_WORK/Formula/millennium-helpers.rb" | head -1)"
FORMULA_BIN_SHA_AFTER="$(grep -E '^\s*sha256\s+"' "$BUMP_WORK/Formula/millennium-helpers-bin.rb" | head -1)"
SCOOP_HASH_AFTER="$(python3 -c "import json; print(json.load(open('$BUMP_WORK/packaging/scoop/millennium-helpers.json'))['hash'])")"
SCOOP_BIN_HASH_AFTER="$(python3 -c "import json; print(json.load(open('$BUMP_WORK/packaging/scoop/millennium-helpers-bin.json'))['hash'])")"
WINGET_SHA_AFTER="$(grep -E '^\s*InstallerSha256:' "$BUMP_WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml" | head -1)"
PKG_SHA_AFTER="$(grep -E "^sha256sums=\('" "$BUMP_WORK/packaging/millennium-helpers/PKGBUILD" | head -1)"
NIX_HASH_AFTER="$(grep -E '^\s*srcAssetHash\s*=' "$BUMP_WORK/nix/release-info.nix" | head -1)"
assert_equals "$FORMULA_SHA_BEFORE" "$FORMULA_SHA_AFTER" "bump-version preserves from-source Formula sha256"
assert_equals "$FORMULA_BIN_SHA_BEFORE" "$FORMULA_BIN_SHA_AFTER" "bump-version preserves bin Formula sha256"
assert_equals "$SCOOP_HASH_BEFORE" "$SCOOP_HASH_AFTER" "bump-version preserves Scoop from-source hash"
assert_equals "$SCOOP_BIN_HASH_BEFORE" "$SCOOP_BIN_HASH_AFTER" "bump-version preserves Scoop-bin hash"
assert_equals "$WINGET_SHA_BEFORE" "$WINGET_SHA_AFTER" "bump-version preserves Winget InstallerSha256"
assert_equals "$PKG_SHA_BEFORE" "$PKG_SHA_AFTER" "bump-version preserves Arch PKGBUILD sha256sums"
assert_equals "$NIX_HASH_BEFORE" "$NIX_HASH_AFTER" "bump-version preserves nix srcAssetHash"

# --- check-version-sync.sh ---

seed_packaging_tree "$CHECK_WORK"
seed_version_only "$CHECK_WORK" "4.5.6"
(cd "$CHECK_WORK" && bash scripts/ci/sync-stable-srcinfo.sh && bash scripts/ci/sync-bin-srcinfo.sh) >/dev/null
out=$(cd "$CHECK_WORK" && bash scripts/ci/check-version-sync.sh 2>&1); rc=$?
assert_success "$rc" "check-version-sync passes on seeded consistent tree"
assert_contains "$out" "pyproject.toml version OK" "check-version-sync validates pyproject.toml"
assert_contains "$out" ".SRCINFO OK" "check-version-sync validates stable .SRCINFO"
assert_contains "$out" "deb/rpm/Chocolatey" "check-version-sync validates deb/rpm/Chocolatey"

sed_inplace 's/^version = .*/version = "0.0.0"/' "$CHECK_WORK/pyproject.toml"
out=$(cd "$CHECK_WORK" && bash scripts/ci/check-version-sync.sh 2>&1); rc=$?
assert_failure "$rc" "check-version-sync fails when pyproject.toml mismatches VERSION"
assert_contains "$out" "pyproject.toml" "check-version-sync names pyproject.toml on mismatch"
sed_inplace 's/^version = .*/version = "4.5.6"/' "$CHECK_WORK/pyproject.toml"

sed_inplace 's|millennium-helpers-v4.5.6-src.tar.gz|millennium-helpers-v4.5.5-src.tar.gz|' \
  "$CHECK_WORK/packaging/millennium-helpers/.SRCINFO"
out=$(cd "$CHECK_WORK" && bash scripts/ci/check-version-sync.sh 2>&1); rc=$?
assert_failure "$rc" "check-version-sync fails when stable .SRCINFO source URL is stale"
assert_contains "$out" ".SRCINFO" "check-version-sync mentions .SRCINFO on drift"

# --- live check scripts on repo ---

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  out=$(bash "$WINGET_CHECK" 2>&1)
  rc=$?
  assert_success "$rc" "check-winget-manifests.sh passes on current manifests"
  assert_contains "$out" "passed" "check-winget-manifests.sh reports success"
  out=$(bash "$PACK_CHECK" 2>&1)
  rc=$?
  assert_success "$rc" "check-packaging-manifests.sh passes on current tree"
  assert_contains "$out" "All packaging manifest checks passed" "check-packaging-manifests.sh reports success"
else
  echo -e "${YELLOW}SKIP:${NC} check-winget / check-packaging (PyYAML not installed)"
fi

# --- release.yml Go assets + Windows zip payload ---
assets_block=$(awk '/Build Go dispatchers and versioned archives/,/Calculate Checksums/' "${REPO_ROOT}/.github/workflows/release.yml")
assert_file_not_exists "${REPO_ROOT}/scripts/millennium-mcp.py" "millennium-mcp.py must not exist (Go MCP only)"
assert_contains "$assets_block" "completions/powershell/" "Windows release zip includes PowerShell completions"
assert_contains "$assets_block" "scripts/windows/millennium.exe" "Windows release zip includes millennium.exe"
assert_not_contains "$assets_block" "scripts/windows/install.ps1" "Windows release zip omits install.ps1"
assert_contains "$assets_block" "windows" "release.yml builds windows helpers zip"
assert_contains "$assets_block" "release_asset_go" "release.yml builds versioned Go dispatchers"
assert_contains "$assets_block" "bin/millennium" "release.yml embeds bin/millennium for Unix tarballs"
assert_contains "$assets_block" "release_asset_src" "release.yml builds versioned -src archives"
assert_not_contains "$assets_block" "scripts/common.sh" "release unix payload omits install-time common.sh"
assert_not_contains "$assets_block" "scripts/lib" "release unix payload omits scripts/lib"
assert_not_contains "$assets_block" "scripts/windows/common.ps1" "release Windows zip omits common.ps1"
assert_not_contains "$assets_block" "scripts/windows/lib/" "release Windows zip omits install-time lib/"

assert_file_not_exists "${REPO_ROOT}/scripts/common.sh" "common.sh removed (Go install owns helpers layout)"
assert_file_not_exists "${REPO_ROOT}/scripts/windows/common.ps1" "common.ps1 removed (Go install owns helpers layout)"
assert_file_not_exists "${REPO_ROOT}/scripts/lib" "scripts/lib removed (release_assets.sh lives in scripts/ci)"
assert_file_not_exists "${REPO_ROOT}/scripts/windows/lib" "scripts/windows/lib removed"
assert_file_not_exists "${REPO_ROOT}/scripts/millennium.sh" "millennium.sh must not exist (Go PATH only)"
assert_file_not_exists "${REPO_ROOT}/scripts/windows/millennium.ps1" "millennium.ps1 must not exist (Go PATH only)"
assert_file_exists "${REPO_ROOT}/scripts/ci/release_assets.sh" "release asset naming helper lives under scripts/ci"
assert_not_contains "$(cat "${REPO_ROOT}/.github/workflows/release.yml")" "scripts/millennium.sh" "release unix payload omits millennium.sh"

release_gate=$(awk '/name: Wait for required CI/,/build-release:/' "${REPO_ROOT}/.github/workflows/release.yml")
assert_contains "$release_gate" "test-suite.yml" "release gate waits on test-suite.yml"
assert_contains "$release_gate" "shellcheck.yml" "release gate waits on shellcheck.yml"
assert_contains "$release_gate" "completions.yml" "release gate waits on completions.yml"
assert_contains "$release_gate" "go.yml" "release gate waits on go.yml"
assert_contains "$release_gate" "version-sync.yml" "release gate waits on version-sync.yml"
assert_contains "$release_gate" "package-manifests.yml" "release gate waits on package-manifests.yml"
assert_contains "$release_gate" "actionlint.yml" "release gate waits on actionlint.yml"
assert_contains "$release_gate" "python-lint.yml" "release gate waits on python-lint.yml"
assert_contains "$release_gate" "powershell-lint.yml" "release gate waits on powershell-lint.yml"
assert_contains "$release_gate" "man-pages.yml" "release gate waits on man-pages.yml"
assert_contains "$release_gate" "sort_by(.createdAt) | last" "release gate requires latest completed CI run"

release_yml=$(cat "${REPO_ROOT}/.github/workflows/release.yml")
assert_contains "$release_yml" "name: Assert skip CI policy" "release refuses skip_ci_gate abuse via assert job"
assert_contains "$release_yml" "skip_ci_gate is only allowed for tag_name=v-draft" "release documents skip_ci_gate=v-draft-only"

for gate_wf in version-sync package-manifests actionlint python-lint powershell-lint man-pages go; do
  wf_body=$(cat "${REPO_ROOT}/.github/workflows/${gate_wf}.yml")
  assert_contains "$wf_body" "tags: [ 'v*' ]" "${gate_wf}.yml declares tags: [v*] for release gate"
done

finalize=$(awk '/Wait for packaging CI, merge, and publish/,/Squash-merging/' "${REPO_ROOT}/.github/workflows/release.yml")
assert_contains "$finalize" "Validate packaging manifests" "release finalize waits on packaging manifests"
assert_contains "$finalize" "Test Scoop-bin Package Install" "release finalize waits on Scoop-bin install"
assert_contains "$finalize" "homebrew (millennium-helpers-bin)" "release finalize waits on Homebrew -bin audit"
assert_contains "$finalize" "Validate AUR packaging (millennium-helpers-bin)" "release finalize waits on Arch -bin"
assert_contains "$finalize" "Build deb from-source" "release finalize waits on deb from-source build"
assert_contains "$finalize" "Validate Chocolatey package" "release finalize waits on Chocolatey validation"
assert_contains "$finalize" "Build Nix Package" "release finalize waits on Nix build"

# --- Workflow path-filter sanity ---
scoop_ci=$(cat "${REPO_ROOT}/.github/workflows/package-install-windows.yml")
assert_contains "$scoop_ci" "millennium-helpers-bin.json" "Scoop CI installs from -bin manifest"
assert_not_contains "$scoop_ci" "millennium-mcp.py" "Scoop CI no longer stages millennium-mcp.py"
assert_contains "$scoop_ci" "completions\\powershell" "Scoop CI stages PowerShell completions in the trimmed zip"
assert_contains "$scoop_ci" "Validate Chocolatey install script shape" "Windows packaging CI validates Chocolatey scripts"
assert_not_contains "$scoop_ci" "- 'README.md'" "Scoop CI path filters do not trigger on README-only docs edits"
assert_not_contains "$scoop_ci" "- 'LICENSE'" "Scoop CI path filters do not trigger on LICENSE-only edits"

nix_wf=$(cat "${REPO_ROOT}/.github/workflows/nix.yml")
assert_contains "$nix_wf" "- 'VERSION'" "Nix CI path filters include VERSION"
assert_contains "$nix_wf" "millennium-helpers-bin" "Nix CI builds -bin package when asset exists"
assert_contains "$nix_wf" "Source release asset not published yet" "Nix CI skips unpublished from-source asset builds"
assert_contains "$nix_wf" "millennium-helpers-git" "Nix CI always builds git package"
assert_not_contains "$nix_wf" "- 'LICENSE'" "Nix CI path filters do not trigger on LICENSE-only edits"

pkg_wf=$(cat "${REPO_ROOT}/.github/workflows/pkgbuild.yml")
assert_contains "$pkg_wf" "- 'VERSION'" "PKGBUILD CI path filters include VERSION"
assert_contains "$pkg_wf" "millennium-helpers-git" "PKGBUILD CI validates -git package"
assert_contains "$pkg_wf" "millennium-helpers-bin" "PKGBUILD CI validates -bin package"
assert_contains "$pkg_wf" "packaging/millennium-helpers/**" "PKGBUILD CI path filters include from-source package"
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
assert_contains "$ps_lint" "tests/windows" "PowerShell lint path filters include tests/windows"
assert_not_contains "$ps_lint" "scripts/windows/**" "PowerShell lint no longer watches removed scripts/windows tree"

for wf in homebrew.yml package-manifests.yml version-sync.yml man-pages.yml python-lint.yml; do
  body=$(cat "${REPO_ROOT}/.github/workflows/${wf}")
  assert_not_contains "$body" "- 'LICENSE'" "${wf} path filters do not trigger on LICENSE-only edits"
  assert_not_contains "$body" "- 'README.md'" "${wf} path filters do not trigger on README-only docs edits"
done

pm=$(cat "${REPO_ROOT}/.github/workflows/package-manifests.yml")
assert_contains "$pm" "packaging/chocolatey/**" "package-manifests watches Chocolatey"
assert_contains "$pm" "packaging/deb/**" "package-manifests watches deb"
assert_contains "$pm" "packaging/rpm/**" "package-manifests watches rpm"
assert_contains "$pm" "packaging/winget-git/**" "package-manifests watches winget-git"
assert_contains "$pm" "Build deb from-source" "package-manifests builds deb from-source"
assert_contains "$pm" "check-packaging-manifests.sh" "package-manifests runs shared check script"

hb=$(cat "${REPO_ROOT}/.github/workflows/homebrew.yml")
assert_contains "$hb" "- 'Formula/**'" "Homebrew CI path filters include Formula"
assert_contains "$hb" "millennium-helpers-bin" "Homebrew CI audits -bin formula"

vs=$(cat "${REPO_ROOT}/.github/workflows/version-sync.yml")
assert_contains "$vs" "- 'VERSION'" "version-sync path filters include VERSION"
assert_contains "$vs" "- 'Formula/**'" "version-sync path filters include Formula"
assert_contains "$vs" "- 'pyproject.toml'" "version-sync path filters include pyproject.toml"
assert_contains "$vs" "sync-stable-srcinfo.sh" "version-sync path filters include sync-stable-srcinfo.sh"
assert_contains "$vs" "sync-bin-srcinfo.sh" "version-sync path filters include sync-bin-srcinfo.sh"
assert_contains "$vs" "packaging/millennium-helpers-bin/**" "version-sync watches Arch -bin"
assert_contains "$vs" "packaging/chocolatey/**" "version-sync watches Chocolatey"
assert_contains "$vs" "bump-version.sh" "version-sync path filters include bump-version.sh"

pre_commit=$(cat "${REPO_ROOT}/.pre-commit-config.yaml")
assert_contains "$pre_commit" "sync-stable-srcinfo" "pre-commit includes sync-stable-srcinfo hook"
assert_contains "$pre_commit" "sync-bin-srcinfo" "pre-commit includes sync-bin-srcinfo hook"
assert_contains "$pre_commit" "sync-git-srcinfo" "pre-commit includes sync-git-srcinfo hook"
assert_contains "$pre_commit" "packaging/millennium-helpers-git" "pre-commit -git SRCINFO sync is recipe-scoped"
assert_not_contains "$pre_commit" "sync-pkgver" "pre-commit no longer always-syncs -git pkgver"
assert_not_contains "$pre_commit" "update-pkgbuild-pkgver" "pre-commit no longer runs update-pkgbuild-pkgver"
assert_contains "$pre_commit" "packaging/millennium-helpers" "pre-commit version-sync watches Arch packaging"
assert_file_exists "${REPO_ROOT}/scripts/ci/sync-git-srcinfo.sh" "sync-git-srcinfo.sh exists"
for sudoers_pkg in millennium-helpers millennium-helpers-bin millennium-helpers-git; do
  sudoers_body=$(cat "${REPO_ROOT}/packaging/${sudoers_pkg}/millennium-helpers.sudoers")
  assert_contains "$sudoers_body" "/usr/bin/millennium upgrade" \
    "${sudoers_pkg} sudoers allowlists Go millennium upgrade"
  assert_not_contains "$sudoers_body" "/usr/bin/millennium-upgrade" \
    "${sudoers_pkg} sudoers omits retired long-name millennium-upgrade"
done

# Completions install only millennium (+ shared millennium-helpers file), not twin names.
arch_install=$(cat "${REPO_ROOT}/packaging/lib/arch-unix-install.sh")
# Intentional literal ${pkgdir} — must match packaging/lib/arch-unix-install.sh source text.
# shellcheck disable=SC2016
assert_contains "$arch_install" \
  'ln -sf millennium-helpers "${pkgdir}/usr/share/bash-completion/completions/millennium"' \
  "Arch packaging symlinks bash completion for millennium only"
assert_not_contains "$arch_install" "for script in millennium-repair" \
  "Arch packaging no longer loops long-name bash completion symlinks"
formula=$(cat "${REPO_ROOT}/Formula/millennium-helpers.rb")
# shellcheck disable=SC2016
assert_contains "$formula" 'bash_completion/"millennium"' \
  "Homebrew formula installs bash completion for millennium"
assert_not_contains "$formula" "millennium-repair" \
  "Homebrew formula no longer lists long-name completion twins"

assert_file_exists "${REPO_ROOT}/scripts/ci/check-packaging-manifests.sh" "check-packaging-manifests.sh exists"
assert_contains "$(cat "${REPO_ROOT}/Makefile")" "sync-git-srcinfo" "Makefile exposes sync-git-srcinfo target"
assert_contains "$(cat "${REPO_ROOT}/Makefile")" "check-packaging" "Makefile exposes check-packaging target"
assert_not_contains "$(cat "${REPO_ROOT}/Makefile")" "sync-pkgver:" "Makefile no longer exposes sync-pkgver target"

makefile=$(cat "${REPO_ROOT}/Makefile")
assert_contains "$makefile" "bump-version" "Makefile exposes bump-version target"
assert_contains "$makefile" "sync-stable-srcinfo" "Makefile exposes sync-stable-srcinfo target"
assert_contains "$makefile" "sync-bin-srcinfo" "Makefile exposes sync-bin-srcinfo target"
# Intentional literal $(VERSION) — Makefile forwards the make variable.
# shellcheck disable=SC2016
assert_contains "$makefile" 'bump-version.sh "$(VERSION)"' "Makefile bump-version forwards VERSION"

print_summary
