#!/usr/bin/env bash
# Verify VERSION matches packaging manifests (Scoop release+from-source, Winget,
# Homebrew source+bin, Arch from-source+-bin + .SRCINFO, Nix, deb/rpm/Chocolatey,
# pyproject.toml). Tip-of-main (*-git / winget-git) packages are excluded.
#
# Usage: make check-version   # or: bash scripts/ci/check-version-sync.sh
# See CONTRIBUTING.md § Versioning.
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
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]] || fail "VERSION '$VERSION' is not a semver-like value"

echo "VERSION=$VERSION"

# --- pyproject.toml ---
PYPROJECT="pyproject.toml"
[[ -f "$PYPROJECT" ]] || fail "missing $PYPROJECT"
PYPROJECT_VERSION="$(python3 -c "
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'(?m)^version\s*=\s*\"([^\"]+)\"', text)
print(m.group(1) if m else '')
" "$PYPROJECT")"
[[ "$PYPROJECT_VERSION" == "$VERSION" ]] || fail "pyproject.toml version '$PYPROJECT_VERSION' != VERSION '$VERSION'"
echo "pyproject.toml version OK ($PYPROJECT_VERSION)"

# --- Scoop from-source + bin ---
for SCOOP_JSON in packaging/scoop/millennium-helpers.json packaging/scoop/millennium-helpers-bin.json; do
  [[ -f "$SCOOP_JSON" ]] || fail "missing $SCOOP_JSON"
  SCOOP_VERSION="$(jq -r '.version' "$SCOOP_JSON")"
  [[ "$SCOOP_VERSION" == "$VERSION" ]] || fail "Scoop version in $SCOOP_JSON is '$SCOOP_VERSION' != VERSION '$VERSION'"
done
echo "Scoop versions OK ($VERSION)"

# --- Winget (all three manifests) ---
for f in packaging/winget/bolens.millenniumhelpers.yaml \
         packaging/winget/bolens.millenniumhelpers.installer.yaml \
         packaging/winget/bolens.millenniumhelpers.locale.en-US.yaml; do
  [[ -f "$f" ]] || fail "missing $f"
  WINGET_VERSION="$(python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as fh:
    data = yaml.safe_load(fh)
print(data.get('PackageVersion', ''))
" "$f")"
  [[ "$WINGET_VERSION" == "$VERSION" ]] || fail "Winget PackageVersion in $f is '$WINGET_VERSION' != VERSION '$VERSION'"
done
echo "Winget PackageVersion OK ($VERSION)"

# --- Homebrew Formulas ---
parse_formula_version() {
  python3 -c "
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^\s*version\s+\"([^\"]+)\"', text, re.M)
if m:
    print(m.group(1)); raise SystemExit(0)
m = re.search(r'releases/download/v([0-9][^\"/]+)/', text)
if m:
    print(m.group(1)); raise SystemExit(0)
m = re.search(r'archive/refs/tags/v([0-9][^\"/]+)\.tar\.gz', text)
if m:
    print(m.group(1)); raise SystemExit(0)
print('')
" "$1"
}

for FORMULA in Formula/millennium-helpers.rb Formula/millennium-helpers-bin.rb; do
  [[ -f "$FORMULA" ]] || fail "missing $FORMULA"
  FORMULA_VERSION="$(parse_formula_version "$FORMULA")"
  [[ -n "$FORMULA_VERSION" ]] || fail "could not parse version from $FORMULA"
  [[ "$FORMULA_VERSION" == "$VERSION" ]] || fail "Homebrew $FORMULA version '$FORMULA_VERSION' != VERSION '$VERSION'"
done
echo "Homebrew Formula versions OK ($VERSION)"

# --- Arch from-source + -bin ---
for AUR_PKGBUILD in packaging/millennium-helpers/PKGBUILD packaging/millennium-helpers-bin/PKGBUILD; do
  [[ -f "$AUR_PKGBUILD" ]] || fail "missing $AUR_PKGBUILD"
  AUR_PKGVER="$(grep -E '^pkgver=' "$AUR_PKGBUILD" | head -1 | cut -d= -f2-)"
  [[ "$AUR_PKGVER" == "$VERSION" ]] || fail "Arch $AUR_PKGBUILD pkgver '$AUR_PKGVER' != VERSION '$VERSION'"
done
# shellcheck disable=SC2016
if ! grep -qE 'archive/refs/tags/v(\$\{pkgver\}|\$pkgver|'"${VERSION}"')\.tar\.gz' packaging/millennium-helpers/PKGBUILD; then
  fail "Arch from-source PKGBUILD missing tag archive URL for v${VERSION}"
fi
# shellcheck disable=SC2016
if ! grep -qE 'releases/download/v(\$\{pkgver\}|\$pkgver|'"${VERSION}"')/millennium-helpers-linux\.tar\.gz' packaging/millennium-helpers-bin/PKGBUILD; then
  fail "Arch -bin PKGBUILD missing trimmed Linux release asset URL for v${VERSION}"
fi
bash scripts/ci/sync-stable-srcinfo.sh --check || fail "Arch from-source .SRCINFO out of date (run: bash scripts/ci/sync-stable-srcinfo.sh)"
bash scripts/ci/sync-bin-srcinfo.sh --check || fail "Arch -bin .SRCINFO out of date (run: bash scripts/ci/sync-bin-srcinfo.sh)"
echo "Arch packaging pkgver/.SRCINFO OK ($VERSION)"

# --- Nix release-info ---
NIX_RELEASE="nix/release-info.nix"
[[ -f "$NIX_RELEASE" ]] || fail "missing $NIX_RELEASE"
NIX_VERSION="$(python3 -c "
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'version\s*=\s*\"([^\"]+)\"', text)
print(m.group(1) if m else '')
" "$NIX_RELEASE")"
[[ "$NIX_VERSION" == "$VERSION" ]] || fail "nix/release-info.nix version '$NIX_VERSION' != VERSION '$VERSION'"
echo "Nix release-info.nix version OK ($NIX_VERSION)"

# --- deb / rpm / Chocolatey (when present) ---
for ctrl in packaging/deb/millennium-helpers/DEBIAN/control packaging/deb/millennium-helpers-bin/DEBIAN/control; do
  [[ -f "$ctrl" ]] || fail "missing $ctrl"
  deb_ver="$(grep -E '^Version:' "$ctrl" | head -1 | awk '{print $2}')"
  [[ "$deb_ver" == "$VERSION" ]] || fail "deb $ctrl Version '$deb_ver' != VERSION '$VERSION'"
done
for spec in packaging/rpm/millennium-helpers.spec packaging/rpm/millennium-helpers-bin.spec; do
  [[ -f "$spec" ]] || fail "missing $spec"
  rpm_ver="$(grep -E '^Version:' "$spec" | head -1 | awk '{print $2}')"
  [[ "$rpm_ver" == "$VERSION" ]] || fail "rpm $spec Version '$rpm_ver' != VERSION '$VERSION'"
done
NUSPEC="packaging/chocolatey/millennium-helpers/millennium-helpers.nuspec"
[[ -f "$NUSPEC" ]] || fail "missing $NUSPEC"
choco_ver="$(python3 -c "
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<version>([^<]+)</version>', text)
print(m.group(1) if m else '')
" "$NUSPEC")"
[[ "$choco_ver" == "$VERSION" ]] || fail "Chocolatey nuspec version '$choco_ver' != VERSION '$VERSION'"
echo "deb/rpm/Chocolatey versions OK ($VERSION)"

# --- Release URL shape ---
python3 - "$VERSION" <<'PY' || fail "packaging release-asset URL checks failed"
import json
import re
import sys
from pathlib import Path

version = sys.argv[1]
errors = []

formula = Path("Formula/millennium-helpers.rb").read_text(encoding="utf-8")
if f"archive/refs/tags/v{version}.tar.gz" not in formula:
    errors.append("Formula from-source URL must use GitHub tag archive")

formula_bin = Path("Formula/millennium-helpers-bin.rb").read_text(encoding="utf-8")
if f"releases/download/v{version}/millennium-helpers-linux.tar.gz" not in formula_bin:
    errors.append("Formula-bin URL must use trimmed Linux release asset")

scoop = json.loads(Path("packaging/scoop/millennium-helpers.json").read_text(encoding="utf-8"))
if f"archive/refs/tags/v{version}.zip" not in str(scoop.get("url", "")):
    errors.append("Scoop from-source URL must use GitHub tag zip")

scoop_bin = json.loads(Path("packaging/scoop/millennium-helpers-bin.json").read_text(encoding="utf-8"))
url = str(scoop_bin.get("url", ""))
if f"releases/download/v{version}/millennium-helpers-windows.zip" not in url:
    errors.append("Scoop-bin URL must use trimmed Windows release asset")
bins = {b[1] if isinstance(b, list) else b for b in scoop_bin.get("bin", [])}
for required in ("millennium", "millennium-mcp", "millennium-diag"):
    if required not in bins:
        errors.append(f"Scoop-bin missing {required!r}")

installer = Path("packaging/winget/bolens.millenniumhelpers.installer.yaml").read_text(encoding="utf-8")
if f"releases/download/v{version}/millennium-helpers-windows.zip" not in installer:
    errors.append("Winget InstallerUrl must use trimmed Windows release asset")

pkg = Path("packaging/millennium-helpers/PKGBUILD").read_text(encoding="utf-8")
if not re.search(
    rf"archive/refs/tags/v(\$\{{pkgver\}}|\$pkgver|{re.escape(version)})\.tar\.gz",
    pkg,
):
    errors.append("Arch from-source PKGBUILD must use tag archive")

pkg_bin = Path("packaging/millennium-helpers-bin/PKGBUILD").read_text(encoding="utf-8")
if not re.search(
    rf"releases/download/v(\$\{{pkgver\}}|\$pkgver|{re.escape(version)})/millennium-helpers-linux\.tar\.gz",
    pkg_bin,
):
    errors.append("Arch -bin PKGBUILD must use trimmed Linux release asset")

if errors:
    for err in errors:
        print(f"error: {err}", file=sys.stderr)
    raise SystemExit(1)
print("Release-asset URL shape OK")
PY

echo "All packaging versions match VERSION ($VERSION)."
