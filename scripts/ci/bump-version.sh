#!/usr/bin/env bash
# Pre-tag version bump: update VERSION + packaging URLs/versions, keep existing hashes.
# Hashes are filled later by release CD via update-packaging-versions.sh.
#
# Usage:
#   scripts/ci/bump-version.sh X.Y.Z
#   make bump-version VERSION=X.Y.Z
#
# Updates: VERSION, pyproject.toml, Formula URL, Scoop version/URL, Winget
# PackageVersion/InstallerUrl/ReleaseDate, versioned Arch PKGBUILD + .SRCINFO,
# nix/release-info.nix version. Does not edit CHANGELOG.md.
#
# See CONTRIBUTING.md § Versioning and docs/release_runbook.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

VERSION="${1:?version required (e.g. 2.5.0)}"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]] || {
  echo "error: invalid version '$VERSION'" >&2
  exit 1
}

REPO="${REPO:-bolens/millenium-helpers}"
ASSET_TGZ="millennium-helpers-linux.tar.gz"
ASSET_ZIP="millennium-helpers-windows.zip"
TAG_URL_TGZ="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_TGZ}"
TAG_URL_ZIP="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_ZIP}"
TODAY="$(date -u +%Y-%m-%d)"

echo "$VERSION" > VERSION
echo "Updated VERSION → $VERSION"

# --- pyproject.toml ---
python3 - "$VERSION" <<'PY'
import re
import sys
from pathlib import Path

version = sys.argv[1]
path = Path("pyproject.toml")
text = path.read_text(encoding="utf-8")
new, n = re.subn(
    r'(?m)^(version\s*=\s*")[^"]*(")',
    rf"\g<1>{version}\g<2>",
    text,
    count=1,
)
if n != 1:
    raise SystemExit(f"error: could not update version in {path}")
path.write_text(new, encoding="utf-8")
print(f"Updated {path}")
PY

# --- Homebrew Formula (URL only; keep sha256) ---
python3 - "$VERSION" "$TAG_URL_TGZ" <<'PY'
import re
import sys
from pathlib import Path

version, url = sys.argv[1], sys.argv[2]
path = Path("Formula/millennium-helpers.rb")
text = path.read_text(encoding="utf-8")
text = re.sub(
    r'url\s+"https://github\.com/[^"]+"',
    f'url "{url}"',
    text,
    count=1,
)
# Drop redundant explicit version when URL encodes the tag.
text = re.sub(r'^\s*version\s+"[^"]+"\n', '', text, count=1, flags=re.M)
path.write_text(text, encoding="utf-8")
print(f"Updated {path}")
PY

# --- Scoop (version + URL; keep hash) ---
python3 - "$VERSION" "$TAG_URL_ZIP" <<'PY'
import json
import sys
from pathlib import Path

version, url = sys.argv[1], sys.argv[2]
path = Path("packaging/scoop/millennium-helpers.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["version"] = version
data["url"] = url
path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

# --- Winget (PackageVersion + InstallerUrl + ReleaseDate; keep sha) ---
python3 - "$VERSION" "$TAG_URL_ZIP" "$TODAY" <<'PY'
import re
import sys
from pathlib import Path

version, url, today = sys.argv[1], sys.argv[2], sys.argv[3]


def set_package_version(text: str, ver: str) -> str:
    return re.sub(
        r"(?m)^PackageVersion:\s*.*$",
        f"PackageVersion: {ver}",
        text,
        count=1,
    )


installer = Path("packaging/winget/bolens.millenniumhelpers.installer.yaml")
text = installer.read_text(encoding="utf-8")
text = set_package_version(text, version)
text = re.sub(r"(?m)^ReleaseDate:\s*.*$", f"ReleaseDate: {today}", text, count=1)
text = re.sub(
    r"(?m)^(\s*)InstallerUrl:\s*.*$",
    rf"\1InstallerUrl: {url}",
    text,
    count=1,
)
installer.write_text(text, encoding="utf-8")
print(f"Updated {installer}")

for rel in (
    "packaging/winget/bolens.millenniumhelpers.yaml",
    "packaging/winget/bolens.millenniumhelpers.locale.en-US.yaml",
):
    path = Path(rel)
    path.write_text(
        set_package_version(path.read_text(encoding="utf-8"), version),
        encoding="utf-8",
    )
    print(f"Updated {path}")
PY

# --- Versioned Arch PKGBUILD (pkgver/pkgrel; keep sha256sums) ---
python3 - "$VERSION" <<'PY'
import re
import sys
from pathlib import Path

version = sys.argv[1]
path = Path("packaging/millennium-helpers/PKGBUILD")
text = path.read_text(encoding="utf-8")
text = re.sub(r"(?m)^pkgver=.*$", f"pkgver={version}", text, count=1)
text = re.sub(r"(?m)^pkgrel=.*$", "pkgrel=1", text, count=1)
path.write_text(text, encoding="utf-8")
print(f"Updated {path}")
PY

bash scripts/ci/sync-stable-srcinfo.sh

# --- Nix release-info.nix (version only; keep srcHash until assets exist) ---
python3 - "$VERSION" <<'PY'
import re
import sys
from pathlib import Path

version = sys.argv[1]
path = Path("nix/release-info.nix")
text = path.read_text(encoding="utf-8")
new, n = re.subn(
    r'(?m)^(\s*version\s*=\s*")[^"]*(";)',
    rf"\g<1>{version}\g<2>",
    text,
    count=1,
)
if n != 1:
    raise SystemExit(f"error: could not update version in {path}")
path.write_text(new, encoding="utf-8")
print(f"Updated {path} (version={version}; srcHash unchanged)")
PY

bash scripts/ci/check-version-sync.sh

echo ""
echo "Pre-tag bump complete for v${VERSION}."
echo "Next:"
echo "  1. Update CHANGELOG.md under ## [${VERSION}] - ${TODAY}"
echo "  2. git add -A && git commit -m 'release: v${VERSION} …'"
echo "  3. After CI is green, tag v${VERSION} (release CD fills real hashes)"
