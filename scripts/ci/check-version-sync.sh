#!/usr/bin/env bash
# Verify VERSION matches packaging manifests (Scoop, Winget, Homebrew).
# Placeholder checksums (all zeros / "skip") are allowed; version strings must match.
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

# --- Release asset URL shape (Homebrew + Scoop) ---
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

if errors:
    for err in errors:
        print(f"error: {err}", file=sys.stderr)
    raise SystemExit(1)
print("Release-asset URL shape OK")
PY

echo "All packaging versions match VERSION ($VERSION)."
