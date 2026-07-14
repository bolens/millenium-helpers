#!/usr/bin/env bash
# Pre-tag version bump: update VERSION + packaging URLs/versions, keep existing hashes.
# Hashes are filled later by release CD via update-packaging-versions.sh.
#
# Usage:
#   scripts/ci/bump-version.sh X.Y.Z
#   make bump-version VERSION=X.Y.Z
#
# Updates: VERSION, pyproject.toml, Formula (+ -bin), Scoop (+ -bin), Winget,
# Arch from-source + -bin PKGBUILD/.SRCINFO, Nix version, deb/rpm/Chocolatey versions.
# Does not edit CHANGELOG.md. Tip-of-main (*-git) packages are excluded.
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
SRC_TAR_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"
SRC_ZIP_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.zip"
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

# --- Homebrew from-source (tag archive URL; keep sha256) ---
python3 - "$VERSION" "$SRC_TAR_URL" <<'PY'
import re
import sys
from pathlib import Path

version, url = sys.argv[1], sys.argv[2]
path = Path("Formula/millennium-helpers.rb")
text = path.read_text(encoding="utf-8")
text = re.sub(r'url\s+"https://github\.com/[^"]+"', f'url "{url}"', text, count=1)
text = re.sub(r'^\s*version\s+"[^"]+"\n', '', text, count=1, flags=re.M)
path.write_text(text, encoding="utf-8")
print(f"Updated {path}")
PY

# --- Homebrew -bin (release tarball URL; keep sha256) ---
python3 - "$VERSION" "$TAG_URL_TGZ" <<'PY'
import re
import sys
from pathlib import Path

version, url = sys.argv[1], sys.argv[2]
path = Path("Formula/millennium-helpers-bin.rb")
text = path.read_text(encoding="utf-8")
text = re.sub(r'url\s+"https://github\.com/[^"]+"', f'url "{url}"', text, count=1)
text = re.sub(r'^\s*version\s+"[^"]+"\n', '', text, count=1, flags=re.M)
path.write_text(text, encoding="utf-8")
print(f"Updated {path}")
PY

# --- Scoop from-source (tag zip) ---
python3 - "$VERSION" "$SRC_ZIP_URL" <<'PY'
import json
import sys
from pathlib import Path

version, url = sys.argv[1], sys.argv[2]
path = Path("packaging/scoop/millennium-helpers.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["version"] = version
data["url"] = url
data["extract_dir"] = f"millenium-helpers-{version}"
if "autoupdate" in data:
    data["autoupdate"]["url"] = "https://github.com/bolens/millenium-helpers/archive/refs/tags/v$version.zip"
    data["autoupdate"]["extract_dir"] = "millenium-helpers-$version"
path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

# --- Scoop -bin (Windows release zip) ---
python3 - "$VERSION" "$TAG_URL_ZIP" <<'PY'
import json
import sys
from pathlib import Path

version, url = sys.argv[1], sys.argv[2]
path = Path("packaging/scoop/millennium-helpers-bin.json")
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
text = re.sub(r"(?m)^(\s*)InstallerUrl:\s*.*$", rf"\1InstallerUrl: {url}", text, count=1)
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

# --- Arch from-source + -bin PKGBUILD (pkgver/pkgrel; keep hashes) ---
python3 - "$VERSION" <<'PY'
import re
import sys
from pathlib import Path

version = sys.argv[1]
for rel in (
    "packaging/millennium-helpers/PKGBUILD",
    "packaging/millennium-helpers-bin/PKGBUILD",
):
    path = Path(rel)
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^pkgver=.*$", f"pkgver={version}", text, count=1)
    text = re.sub(r"(?m)^pkgrel=.*$", "pkgrel=1", text, count=1)
    path.write_text(text, encoding="utf-8")
    print(f"Updated {path}")
PY

bash scripts/ci/sync-stable-srcinfo.sh
bash scripts/ci/sync-bin-srcinfo.sh

# --- Nix release-info.nix (version only) ---
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
print(f"Updated {path} (version={version}; hashes unchanged)")
PY

# --- deb / rpm / Chocolatey versions (keep checksums) ---
python3 - "$VERSION" <<'PY'
import re
import sys
from pathlib import Path

version = sys.argv[1]

for rel in (
    "packaging/deb/millennium-helpers/DEBIAN/control",
    "packaging/deb/millennium-helpers-bin/DEBIAN/control",
):
    path = Path(rel)
    if not path.exists():
        continue
    text = re.sub(r"(?m)^Version:\s*.*$", f"Version: {version}", path.read_text(encoding="utf-8"), count=1)
    path.write_text(text, encoding="utf-8")
    print(f"Updated {path}")

for rel in (
    "packaging/rpm/millennium-helpers.spec",
    "packaging/rpm/millennium-helpers-bin.spec",
):
    path = Path(rel)
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^Version:\s*.*$", f"Version: {version}", text, count=1)
    text = re.sub(r"(?m)^Release:\s*.*$", "Release: 1%{?dist}", text, count=1)
    path.write_text(text, encoding="utf-8")
    print(f"Updated {path}")

nuspec = Path("packaging/chocolatey/millennium-helpers/millennium-helpers.nuspec")
if nuspec.exists():
    text = re.sub(
        r"<version>[^<]+</version>",
        f"<version>{version}</version>",
        nuspec.read_text(encoding="utf-8"),
        count=1,
    )
    nuspec.write_text(text, encoding="utf-8")
    print(f"Updated {nuspec}")

choco = Path("packaging/chocolatey/millennium-helpers/tools/chocolateyInstall.ps1")
if choco.exists():
    text = re.sub(
        r"(\$version\s*=\s*')[^']+(')",
        rf"\g<1>{version}\g<2>",
        choco.read_text(encoding="utf-8"),
        count=1,
    )
    choco.write_text(text, encoding="utf-8")
    print(f"Updated {choco}")
PY

bash scripts/ci/check-version-sync.sh

echo ""
echo "Pre-tag bump complete for v${VERSION}."
echo "Next:"
echo "  1. Update CHANGELOG.md under ## [${VERSION}] - ${TODAY}"
echo "  2. git add -A && git commit -m 'release: v${VERSION} …'"
echo "  3. After CI is green, tag v${VERSION} (release CD fills real hashes)"
