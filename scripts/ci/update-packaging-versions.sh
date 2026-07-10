#!/usr/bin/env bash
# Update Formula / Scoop / Winget packaging files for a release tag.
# Usage: update-packaging-versions.sh <version> <linux_sha256> <windows_sha256>
#   version: semver without leading v (e.g. 2.2.0)
#   linux_sha256: SHA256 of GitHub source tarball (archive/refs/tags/vX.Y.Z.tar.gz)
#   windows_sha256: SHA256 of GitHub source zip (archive/refs/tags/vX.Y.Z.zip)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

VERSION="${1:?version required (e.g. 2.2.0)}"
LINUX_SHA="${2:?linux/source tarball sha256 required}"
WINDOWS_SHA="${3:?windows zip sha256 required}"

VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]] || {
  echo "error: invalid version '$VERSION'" >&2
  exit 1
}
[[ "$LINUX_SHA" =~ ^[0-9a-fA-F]{64}$ ]] || {
  echo "error: linux sha256 must be 64 hex chars" >&2
  exit 1
}
[[ "$WINDOWS_SHA" =~ ^[0-9a-fA-F]{64}$ ]] || {
  echo "error: windows sha256 must be 64 hex chars" >&2
  exit 1
}
# Reject placeholder hashes so packaging never ships all-zero checksums.
if [[ "${LINUX_SHA,,}" =~ ^0{64}$ || "${WINDOWS_SHA,,}" =~ ^0{64}$ ]]; then
  echo "error: refusing placeholder all-zero sha256" >&2
  exit 1
fi

LINUX_SHA="${LINUX_SHA,,}"
WINDOWS_SHA="${WINDOWS_SHA,,}"

TAG_URL_TGZ="https://github.com/bolens/millenium-helpers/archive/refs/tags/v${VERSION}.tar.gz"
TAG_URL_ZIP="https://github.com/bolens/millenium-helpers/archive/refs/tags/v${VERSION}.zip"
TODAY="$(date -u +%Y-%m-%d)"

echo "$VERSION" > VERSION
echo "Updated VERSION → $VERSION"

# --- Homebrew Formula ---
python3 - "$VERSION" "$LINUX_SHA" "$TAG_URL_TGZ" <<'PY'
import re
import sys
from pathlib import Path

version, sha, url = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
path = Path("Formula/millennium-helpers.rb")
text = path.read_text(encoding="utf-8")

text = re.sub(
    r'url\s+"https://github\.com/bolens/millenium-helpers/archive/refs/tags/v[^"]+"',
    f'url "{url}"',
    text,
    count=1,
)
text = re.sub(
    r'sha256\s+"[0-9a-fA-F]{64}"',
    f'sha256 "{sha}"',
    text,
    count=1,
)
if re.search(r'^\s*version\s+"', text, re.M):
    text = re.sub(
        r'^\s*version\s+"[^"]+"',
        f'  version "{version}"',
        text,
        count=1,
        flags=re.M,
    )
else:
    text = re.sub(
        r'(homepage\s+"[^"]+"\n)',
        rf'\1  version "{version}"\n',
        text,
        count=1,
    )

path.write_text(text, encoding="utf-8")
print(f"Updated {path}")
PY

# --- Scoop ---
python3 - "$VERSION" "$WINDOWS_SHA" "$TAG_URL_ZIP" <<'PY'
import json
import sys
from pathlib import Path

version, sha, url = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
path = Path("packaging/scoop/millennium-helpers.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["version"] = version
data["url"] = url
data["hash"] = sha
path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

# --- Winget (string edits preserve comments) ---
python3 - "$VERSION" "$WINDOWS_SHA" "$TAG_URL_ZIP" "$TODAY" <<'PY'
import re
import sys
from pathlib import Path

version, sha, url, today = sys.argv[1], sys.argv[2].upper(), sys.argv[3], sys.argv[4]


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
text = re.sub(
    r"(?m)^(\s*)InstallerSha256:\s*.*$",
    rf'\1InstallerSha256: "{sha}"',
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

# Verify written manifests contain the expected hashes (catch silent regex misses).
python3 - "$VERSION" "$LINUX_SHA" "$WINDOWS_SHA" <<'PY'
import json
import re
import sys
from pathlib import Path

version, linux_sha, windows_sha = sys.argv[1], sys.argv[2].lower(), sys.argv[3].lower()
errors: list[str] = []

formula = Path("Formula/millennium-helpers.rb").read_text(encoding="utf-8")
if f'sha256 "{linux_sha}"' not in formula:
    errors.append("Formula/millennium-helpers.rb missing expected sha256")
if f'v{version}.tar.gz' not in formula:
    errors.append("Formula/millennium-helpers.rb missing expected tag URL")

scoop = json.loads(Path("packaging/scoop/millennium-helpers.json").read_text(encoding="utf-8"))
if scoop.get("version") != version:
    errors.append(f"Scoop version {scoop.get('version')!r} != {version!r}")
if str(scoop.get("hash", "")).lower() != windows_sha:
    errors.append("Scoop hash mismatch")
if f"v{version}.zip" not in str(scoop.get("url", "")):
    errors.append("Scoop URL missing expected tag zip")

installer = Path("packaging/winget/bolens.millenniumhelpers.installer.yaml").read_text(
    encoding="utf-8"
)
if not re.search(rf'(?m)^\s*InstallerSha256:\s*"{windows_sha.upper()}"\s*(#.*)?$', installer):
    errors.append("Winget InstallerSha256 missing expected quoted hash")
if f"v{version}.zip" not in installer:
    errors.append("Winget InstallerUrl missing expected tag zip")
if f"PackageVersion: {version}" not in installer:
    errors.append("Winget installer PackageVersion mismatch")

file_ver = Path("VERSION").read_text(encoding="utf-8").strip()
if file_ver != version:
    errors.append(f"VERSION file {file_ver!r} != {version!r}")

if errors:
    for err in errors:
        print(f"error: {err}", file=sys.stderr)
    raise SystemExit(1)

print("Verified packaging hashes and versions after update.")
PY

echo "Packaging files updated for v${VERSION}."
