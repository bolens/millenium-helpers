#!/usr/bin/env bash
# Update Formula / Scoop / Winget / versioned Arch / Nix packaging for a release tag.
# Usage: update-packaging-versions.sh <version> <linux_sha256> <windows_sha256> [repo]
#   version: semver without leading v (e.g. 2.2.0)
#   linux_sha256: SHA256 of trimmed Linux release asset (millennium-helpers-linux.tar.gz)
#   windows_sha256: SHA256 of trimmed Windows release asset (millennium-helpers-windows.zip)
#   repo: optional GitHub owner/name (default: bolens/millenium-helpers)
#
# Note: packaging/millennium-helpers-git is tip-of-main and is not updated here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

VERSION="${1:?version required (e.g. 2.2.0)}"
LINUX_SHA="${2:?linux release-asset sha256 required}"
WINDOWS_SHA="${3:?windows release-asset sha256 required}"
REPO="${4:-bolens/millenium-helpers}"

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
# Use tr (not ${var,,}) so this works on macOS Bash 3.2.
LINUX_SHA_LC="$(printf '%s' "$LINUX_SHA" | tr '[:upper:]' '[:lower:]')"
WINDOWS_SHA_LC="$(printf '%s' "$WINDOWS_SHA" | tr '[:upper:]' '[:lower:]')"
if [[ "$LINUX_SHA_LC" =~ ^0{64}$ || "$WINDOWS_SHA_LC" =~ ^0{64}$ ]]; then
  echo "error: refusing placeholder all-zero sha256" >&2
  exit 1
fi
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo "error: repo must look like owner/name (got '$REPO')" >&2
  exit 1
}

LINUX_SHA="$LINUX_SHA_LC"
WINDOWS_SHA="$WINDOWS_SHA_LC"
ASSET_TGZ="millennium-helpers-linux.tar.gz"
ASSET_ZIP="millennium-helpers-windows.zip"
TAG_URL_TGZ="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_TGZ}"
TAG_URL_ZIP="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_ZIP}"
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
    r'url\s+"https://github\.com/[^"]+"',
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
# Drop an explicit version line when the stable URL already encodes the
# tag — brew audit flags a redundant version as an error.
text = re.sub(r'^\s*version\s+"[^"]+"\n', '', text, count=1, flags=re.M)

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
data["autoupdate"] = {
    "url": "https://github.com/bolens/millenium-helpers/releases/download/v$version/millennium-helpers-windows.zip",
    "hash": {
        "url": "https://github.com/bolens/millenium-helpers/releases/download/v$version/millennium-helpers-windows.zip.sha256"
    },
}
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

# --- Versioned Arch PKGBUILD (release tarball; -git is separate) ---
python3 - "$VERSION" "$LINUX_SHA" <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

version, linux_sha = sys.argv[1], sys.argv[2].lower()
pkg_dir = Path("packaging/millennium-helpers")
pkgbuild = pkg_dir / "PKGBUILD"
text = pkgbuild.read_text(encoding="utf-8")

text = re.sub(r"(?m)^pkgver=.*$", f"pkgver={version}", text, count=1)
text = re.sub(r"(?m)^pkgrel=.*$", "pkgrel=1", text, count=1)
# First sha256sums entry is the Linux release tarball; keep sudoers hash.
text = re.sub(
    r"(?m)^(sha256sums=\(')[0-9a-fA-F]{64}(')",
    rf"\g<1>{linux_sha}\g<2>",
    text,
    count=1,
)

pkgbuild.write_text(text, encoding="utf-8")
print(f"Updated {pkgbuild}")

srcinfo = pkg_dir / ".SRCINFO"
try:
    if os.geteuid() == 0:
        raise FileNotFoundError("makepkg unavailable as root")
    generated = subprocess.check_output(
        ["makepkg", "--printsrcinfo"],
        cwd=pkg_dir,
        text=True,
    )
    srcinfo.write_text(generated, encoding="utf-8")
    print(f"Regenerated {srcinfo}")
except (FileNotFoundError, subprocess.CalledProcessError, OSError) as exc:
    # Fallback when makepkg is unavailable (e.g. non-Arch runners): patch fields.
    if not srcinfo.is_file():
        raise SystemExit(f"error: cannot regenerate {srcinfo}: {exc}") from exc
    info = srcinfo.read_text(encoding="utf-8")
    info = re.sub(r"(?m)^(\tpkgver = ).*$", rf"\g<1>{version}", info, count=1)
    info = re.sub(r"(?m)^(\tpkgrel = ).*$", r"\g<1>1", info, count=1)
    info = re.sub(
        r"(?m)^(source = https://github\.com/.+/releases/download/)v[^/]+(/millennium-helpers-linux\.tar\.gz)$",
        rf"\g<1>v{version}\g<2>",
        info,
        count=1,
    )
    # First sha256sums line is the tarball.
    info = re.sub(
        r"(?m)^(sha256sums = )[0-9a-fA-F]{64}$",
        rf"\g<1>{linux_sha}",
        info,
        count=1,
    )
    srcinfo.write_text(info, encoding="utf-8")
    print(f"Patched {srcinfo} (makepkg unavailable)")
PY

# --- Nix release-info.nix (SRI hash of Linux release tarball) ---
python3 - "$VERSION" "$LINUX_SHA" <<'PY'
import base64
import binascii
import re
import sys
from pathlib import Path

version, linux_sha = sys.argv[1], sys.argv[2].lower()
sri = "sha256-" + base64.b64encode(binascii.unhexlify(linux_sha)).decode("ascii")
path = Path("nix/release-info.nix")
text = path.read_text(encoding="utf-8")
text = re.sub(r'(?m)^(\s*version\s*=\s*")[^"]*(";)', rf"\g<1>{version}\g<2>", text, count=1)
text = re.sub(
    r'(?m)^(\s*srcHash\s*=\s*")[^"]*(";)',
    rf"\g<1>{sri}\g<2>",
    text,
    count=1,
)
path.write_text(text, encoding="utf-8")
print(f"Updated {path} (version={version}, srcHash={sri})")
PY

# Verify written manifests contain the expected hashes (catch silent regex misses).
python3 - "$VERSION" "$LINUX_SHA" "$WINDOWS_SHA" "$ASSET_TGZ" "$ASSET_ZIP" <<'PY'
import base64
import binascii
import json
import re
import sys
from pathlib import Path

version, linux_sha, windows_sha, asset_tgz, asset_zip = (
    sys.argv[1],
    sys.argv[2].lower(),
    sys.argv[3].lower(),
    sys.argv[4],
    sys.argv[5],
)
errors: list[str] = []

formula = Path("Formula/millennium-helpers.rb").read_text(encoding="utf-8")
if f'sha256 "{linux_sha}"' not in formula:
    errors.append("Formula/millennium-helpers.rb missing expected sha256")
if f"releases/download/v{version}/{asset_tgz}" not in formula:
    errors.append("Formula/millennium-helpers.rb missing expected release asset URL")

scoop = json.loads(Path("packaging/scoop/millennium-helpers.json").read_text(encoding="utf-8"))
if scoop.get("version") != version:
    errors.append(f"Scoop version {scoop.get('version')!r} != {version!r}")
if str(scoop.get("hash", "")).lower() != windows_sha:
    errors.append("Scoop hash mismatch")
if f"releases/download/v{version}/{asset_zip}" not in str(scoop.get("url", "")):
    errors.append("Scoop URL missing expected Windows release asset")
autoupdate = scoop.get("autoupdate") or {}
if "millennium-helpers-windows.zip" not in str(autoupdate.get("url", "")):
    errors.append("Scoop autoupdate URL missing Windows release asset")
hash_url = (autoupdate.get("hash") or {}).get("url", "")
if "millennium-helpers-windows.zip.sha256" not in str(hash_url):
    errors.append("Scoop autoupdate hash URL missing .sha256 sidecar")

installer = Path("packaging/winget/bolens.millenniumhelpers.installer.yaml").read_text(
    encoding="utf-8"
)
if not re.search(rf'(?m)^\s*InstallerSha256:\s*"{windows_sha.upper()}"\s*(#.*)?$', installer):
    errors.append("Winget InstallerSha256 missing expected quoted hash")
if f"releases/download/v{version}/{asset_zip}" not in installer:
    errors.append("Winget InstallerUrl missing expected Windows release asset")
if f"PackageVersion: {version}" not in installer:
    errors.append("Winget installer PackageVersion mismatch")

pkgbuild = Path("packaging/millennium-helpers/PKGBUILD").read_text(encoding="utf-8")
if not re.search(rf"(?m)^pkgver={re.escape(version)}$", pkgbuild):
    errors.append("Arch packaging/millennium-helpers/PKGBUILD pkgver mismatch")
if not re.search(
    rf"releases/download/v(\$\{{pkgver\}}|\$pkgver|{re.escape(version)})/{re.escape(asset_tgz)}",
    pkgbuild,
):
    errors.append("Arch PKGBUILD missing expected Linux release asset URL")
if linux_sha not in pkgbuild:
    errors.append("Arch PKGBUILD missing expected Linux sha256")

release_info = Path("nix/release-info.nix").read_text(encoding="utf-8")
if f'version = "{version}"' not in release_info:
    errors.append("nix/release-info.nix version mismatch")
sri = "sha256-" + base64.b64encode(binascii.unhexlify(linux_sha)).decode("ascii")
if f'srcHash = "{sri}"' not in release_info:
    errors.append("nix/release-info.nix srcHash mismatch")

file_ver = Path("VERSION").read_text(encoding="utf-8").strip()
if file_ver != version:
    errors.append(f"VERSION file {file_ver!r} != {version!r}")

if errors:
    for err in errors:
        print(f"error: {err}", file=sys.stderr)
    raise SystemExit(1)

print("Verified packaging hashes and versions after update.")
PY

echo "Packaging files updated for v${VERSION} (trimmed release assets)."
