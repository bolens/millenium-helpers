#!/usr/bin/env bash
# Structural validation for VERSION-tied packaging surfaces (Scoop, Winget,
# Chocolatey, deb, rpm) plus tip-of-main Scoop/Winget-git shape checks.
# Prefer: make check-packaging
# See packaging/README.md and CONTRIBUTING.md § Versioning.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$*" >&2
  echo "error: $*" >&2
  exit 1
}

[[ -f VERSION ]] || fail "VERSION file is missing"
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ -n "$VERSION" ]] || fail "VERSION file is empty"

echo "Checking packaging manifests for VERSION=$VERSION"

require_bins() {
  local manifest="$1"
  shift
  local bin
  for bin in "$@"; do
    jq -e --arg b "$bin" '.bin | flatten | index($b)' "$manifest" >/dev/null \
      || fail "$manifest bin list missing '$bin'"
  done
}

# --- Scoop: from-source / bin / git ---
for f in packaging/scoop/millennium-helpers.json \
         packaging/scoop/millennium-helpers-bin.json \
         packaging/scoop/millennium-helpers-git.json; do
  [[ -f "$f" ]] || fail "missing $f"
  jq . "$f" >/dev/null || fail "invalid JSON: $f"
done

scoop_src=packaging/scoop/millennium-helpers.json
url="$(jq -r .url "$scoop_src")"
[[ "$url" == *"archive/refs/tags/v${VERSION}.zip" ]] \
  || fail "Scoop from-source url must be tag zip for v${VERSION}, got: $url"
extract_dir="$(jq -r .extract_dir "$scoop_src")"
[[ "$extract_dir" == "millenium-helpers-${VERSION}" ]] \
  || fail "Scoop from-source extract_dir must be millenium-helpers-${VERSION}, got: $extract_dir"
require_bins "$scoop_src" millennium millennium-mcp millennium-diag
echo "Scoop from-source OK"

scoop_bin=packaging/scoop/millennium-helpers-bin.json
url="$(jq -r .url "$scoop_bin")"
[[ "$url" == *"/releases/download/v${VERSION}/millennium-helpers-windows.zip" ]] \
  || fail "Scoop-bin url must be trimmed Windows release zip, got: $url"
hash_url="$(jq -r '.autoupdate.hash.url // empty' "$scoop_bin")"
[[ "$hash_url" == *"/millennium-helpers-windows.zip.sha256" ]] \
  || fail "Scoop-bin autoupdate.hash.url must point at .sha256 sidecar, got: $hash_url"
require_bins "$scoop_bin" millennium millennium-mcp millennium-diag
echo "Scoop-bin OK"

scoop_git=packaging/scoop/millennium-helpers-git.json
[[ "$(jq -r .version "$scoop_git")" == "nightly" ]] \
  || fail "Scoop-git version must be nightly"
url="$(jq -r .url "$scoop_git")"
[[ "$url" == *"archive/refs/heads/main.zip" ]] \
  || fail "Scoop-git url must be main.zip, got: $url"
[[ "$(jq -r .extract_dir "$scoop_git")" == "millenium-helpers-main" ]] \
  || fail "Scoop-git extract_dir must be millenium-helpers-main"
require_bins "$scoop_git" millennium millennium-mcp millennium-diag
echo "Scoop-git OK"

# --- Winget release + git ---
bash scripts/ci/check-winget-manifests.sh

winget_git_dir=packaging/winget-git
[[ -f "$winget_git_dir/bolens.millenniumhelpers.git.yaml" ]] \
  || fail "missing winget-git version manifest"
[[ -f "$winget_git_dir/bolens.millenniumhelpers.git.installer.yaml" ]] \
  || fail "missing winget-git installer manifest"
if ! grep -q 'archive/refs/heads/main.zip' \
  "$winget_git_dir/bolens.millenniumhelpers.git.installer.yaml"; then
  fail "winget-git installer must point at main.zip"
fi
echo "Winget-git OK"

# --- Chocolatey (bin) ---
nuspec=packaging/chocolatey/millennium-helpers/millennium-helpers.nuspec
install_ps1=packaging/chocolatey/millennium-helpers/tools/chocolateyInstall.ps1
uninstall_ps1=packaging/chocolatey/millennium-helpers/tools/chocolateyUninstall.ps1
[[ -f "$nuspec" ]] || fail "missing $nuspec"
[[ -f "$install_ps1" ]] || fail "missing $install_ps1"
[[ -f "$uninstall_ps1" ]] || fail "missing $uninstall_ps1"
choco_ver="$(python3 -c "
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<version>([^<]+)</version>', text)
print(m.group(1) if m else '')
" "$nuspec")"
[[ "$choco_ver" == "$VERSION" ]] || fail "Chocolatey nuspec version '$choco_ver' != VERSION '$VERSION'"
grep -q "millennium-helpers-windows.zip" "$install_ps1" \
  || fail "Chocolatey install script must reference Windows release zip"
grep -qE "\\\$version\s*=\s*'${VERSION}'" "$install_ps1" \
  || fail "Chocolatey install script \$version must match VERSION"
echo "Chocolatey OK"

# --- deb ---
for ctrl in packaging/deb/millennium-helpers/DEBIAN/control \
            packaging/deb/millennium-helpers-bin/DEBIAN/control; do
  [[ -f "$ctrl" ]] || fail "missing $ctrl"
  deb_ver="$(grep -E '^Version:' "$ctrl" | head -1 | awk '{print $2}')"
  [[ "$deb_ver" == "$VERSION" ]] || fail "$ctrl Version '$deb_ver' != VERSION '$VERSION'"
  grep -qE '^Package:' "$ctrl" || fail "$ctrl missing Package field"
  grep -qE '^Architecture:' "$ctrl" || fail "$ctrl missing Architecture field"
done
grep -q '^Package: millennium-helpers$' packaging/deb/millennium-helpers/DEBIAN/control \
  || fail "deb from-source Package must be millennium-helpers"
grep -q '^Package: millennium-helpers-bin$' packaging/deb/millennium-helpers-bin/DEBIAN/control \
  || fail "deb-bin Package must be millennium-helpers-bin"
[[ -x packaging/deb/build-bin.sh ]] || fail "packaging/deb/build-bin.sh must be executable"
[[ -x packaging/deb/build-from-source.sh ]] || fail "packaging/deb/build-from-source.sh must be executable"
echo "deb packaging OK"

# --- rpm ---
for spec in packaging/rpm/millennium-helpers.spec packaging/rpm/millennium-helpers-bin.spec; do
  [[ -f "$spec" ]] || fail "missing $spec"
  rpm_ver="$(grep -E '^Version:' "$spec" | head -1 | awk '{print $2}')"
  [[ "$rpm_ver" == "$VERSION" ]] || fail "$spec Version '$rpm_ver' != VERSION '$VERSION'"
  grep -qE '^Name:' "$spec" || fail "$spec missing Name"
  grep -qE '^Source0:' "$spec" || fail "$spec missing Source0"
done
grep -q 'archive/refs/tags/v%{version}.tar.gz' packaging/rpm/millennium-helpers.spec \
  || fail "rpm from-source Source0 must be tag archive"
grep -q 'millennium-helpers-linux.tar.gz' packaging/rpm/millennium-helpers-bin.spec \
  || fail "rpm-bin Source0 must be Linux release tarball"
echo "rpm packaging OK"

# --- Formula files present (Homebrew CI audits deeply) ---
[[ -f Formula/millennium-helpers.rb ]] || fail "missing Formula/millennium-helpers.rb"
[[ -f Formula/millennium-helpers-bin.rb ]] || fail "missing Formula/millennium-helpers-bin.rb"
grep -q 'archive/refs/tags/' Formula/millennium-helpers.rb \
  || fail "Formula from-source must use tag archive URL"
grep -q 'millennium-helpers-linux.tar.gz' Formula/millennium-helpers-bin.rb \
  || fail "Formula-bin must use Linux release tarball"
echo "Homebrew Formula files OK"

echo "All packaging manifest checks passed."
