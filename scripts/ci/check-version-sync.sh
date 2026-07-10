#!/usr/bin/env bash
# Verify VERSION matches packaging manifests (Scoop release, Winget, Homebrew, versioned Arch).
# Placeholder checksums (all zeros / "skip") are allowed; version strings must match.
# packaging/millennium-helpers-git and packaging/scoop/millennium-helpers-git.json track tip-of-main
# and are not checked here. nix packages.millennium-helpers-git builds from the flake source similarly.
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

# --- Scoop ---
SCOOP_JSON="packaging/scoop/millennium-helpers.json"
[[ -f "$SCOOP_JSON" ]] || fail "missing $SCOOP_JSON"
SCOOP_VERSION="$(jq -r '.version' "$SCOOP_JSON")"
[[ "$SCOOP_VERSION" == "$VERSION" ]] || fail "Scoop version '$SCOOP_VERSION' != VERSION '$VERSION'"
echo "Scoop version OK ($SCOOP_VERSION)"

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

# --- Homebrew Formula ---
FORMULA="Formula/millennium-helpers.rb"
[[ -f "$FORMULA" ]] || fail "missing $FORMULA"
# Prefer an explicit version "x.y.z" line; fall back to the tag in the stable url.
# (brew audit rejects a redundant version when the URL already encodes the tag,
# so packaging updates keep only the URL-derived version.)
FORMULA_VERSION="$(python3 -c "
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^\s*version\s+\"([^\"]+)\"', text, re.M)
if m:
    print(m.group(1))
    raise SystemExit(0)
m = re.search(r'releases/download/v([0-9][^\"/]+)/', text)
if m:
    print(m.group(1))
    raise SystemExit(0)
m = re.search(r'archive/refs/tags/v([0-9][^\"/]+)\.tar\.gz', text)
if m:
    print(m.group(1))
    raise SystemExit(0)
print('')
" "$FORMULA")"
[[ -n "$FORMULA_VERSION" ]] || fail "could not parse version from $FORMULA"
[[ "$FORMULA_VERSION" == "$VERSION" ]] || fail "Homebrew Formula version '$FORMULA_VERSION' != VERSION '$VERSION'"
echo "Homebrew Formula version OK ($FORMULA_VERSION)"

# --- Versioned Arch PKGBUILD ---
AUR_PKGBUILD="packaging/millennium-helpers/PKGBUILD"
[[ -f "$AUR_PKGBUILD" ]] || fail "missing $AUR_PKGBUILD"
AUR_PKGVER="$(grep -E '^pkgver=' "$AUR_PKGBUILD" | head -1 | cut -d= -f2-)"
[[ "$AUR_PKGVER" == "$VERSION" ]] || fail "Arch PKGBUILD pkgver '$AUR_PKGVER' != VERSION '$VERSION'"
# URL may embed ${pkgver} / $pkgver or a literal vX.Y.Z — both are valid.
# shellcheck disable=SC2016 # intentional literal ${pkgver}/$pkgver in the PKGBUILD pattern
if ! grep -qE 'releases/download/v(\$\{pkgver\}|\$pkgver|'"${VERSION}"')/millennium-helpers-linux\.tar\.gz' "$AUR_PKGBUILD"; then
  fail "Arch PKGBUILD missing trimmed Linux release asset URL for v${VERSION}"
fi
echo "Arch packaging/millennium-helpers pkgver OK ($AUR_PKGVER)"

# --- Versioned Arch .SRCINFO (must match PKGBUILD; catches hand-edited drift) ---
AUR_SRCINFO="packaging/millennium-helpers/.SRCINFO"
[[ -f "$AUR_SRCINFO" ]] || fail "missing $AUR_SRCINFO"
bash scripts/ci/sync-stable-srcinfo.sh --check || fail "Arch .SRCINFO out of date with PKGBUILD (run: bash scripts/ci/sync-stable-srcinfo.sh)"
echo "Arch packaging/millennium-helpers .SRCINFO OK"

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

# --- Release asset URL shape (Homebrew + Scoop + Arch) ---
python3 - "$VERSION" <<'PY' || fail "packaging release-asset URL checks failed"
import json
import re
import sys
from pathlib import Path

version = sys.argv[1]
errors = []

formula = Path("Formula/millennium-helpers.rb").read_text(encoding="utf-8")
if f"releases/download/v{version}/millennium-helpers-linux.tar.gz" not in formula:
    errors.append("Formula URL must use trimmed Linux release asset")

scoop = json.loads(Path("packaging/scoop/millennium-helpers.json").read_text(encoding="utf-8"))
url = str(scoop.get("url", ""))
if f"releases/download/v{version}/millennium-helpers-windows.zip" not in url:
    errors.append("Scoop URL must use trimmed Windows release asset")
bins = {b[1] if isinstance(b, list) else b for b in scoop.get("bin", [])}
for required in ("millennium", "millennium-mcp", "millennium-diag"):
    if required not in bins:
        errors.append(f"Scoop bin missing {required!r}")

installer = Path("packaging/winget/bolens.millenniumhelpers.installer.yaml").read_text(encoding="utf-8")
if f"releases/download/v{version}/millennium-helpers-windows.zip" not in installer:
    errors.append("Winget InstallerUrl must use trimmed Windows release asset")

pkgbuild = Path("packaging/millennium-helpers/PKGBUILD").read_text(encoding="utf-8")
if not re.search(
    rf"releases/download/v(\$\{{pkgver\}}|\$pkgver|{re.escape(version)})/millennium-helpers-linux\.tar\.gz",
    pkgbuild,
):
    errors.append("Arch PKGBUILD URL must use trimmed Linux release asset")

if errors:
    for err in errors:
        print(f"error: {err}", file=sys.stderr)
    raise SystemExit(1)
print("Release-asset URL shape OK")
PY

echo "All packaging versions match VERSION ($VERSION)."
