#!/usr/bin/env bash
# Update Formula / Scoop / Winget / Arch / Nix / deb / rpm / Chocolatey for a release tag.
# Usage:
#   update-packaging-versions.sh <version> <linux_sha256> <windows_sha256> [repo] [tag_tar_sha] [tag_zip_sha]
#
#   version: semver without leading v (e.g. 2.2.0)
#   linux_sha256: SHA256 of millennium-helpers-linux.tar.gz (bin)
#   windows_sha256: SHA256 of millennium-helpers-windows.zip (bin)
#   repo: optional GitHub owner/name (default: bolens/millenium-helpers)
#   tag_tar_sha / tag_zip_sha: optional SHA256 of GitHub tag archives; fetched if omitted
#
# Matrix:
#   from-source → Formula/millennium-helpers, Scoop plain, Arch packaging/millennium-helpers, Nix srcGitHash
#   bin         → Formula-bin, Scoop-bin, Arch-bin, Winget, Nix srcAssetHash, Chocolatey, deb/rpm-bin
#   git         → not updated here
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

VERSION="${1:?version required (e.g. 2.2.0)}"
LINUX_SHA="${2:?linux release-asset sha256 required}"
WINDOWS_SHA="${3:?windows release-asset sha256 required}"
REPO="${4:-bolens/millenium-helpers}"
TAG_TAR_SHA="${5:-}"
TAG_ZIP_SHA="${6:-}"

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
SRC_TAR_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"
SRC_ZIP_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.zip"
TODAY="$(date -u +%Y-%m-%d)"

fetch_sha() {
  local url="$1"
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL "$url" -o "$tmp"; then
    rm -f "$tmp"
    echo "error: failed to download $url" >&2
    exit 1
  fi
  sha256sum "$tmp" | awk '{print $1}'
  rm -f "$tmp"
}

if [[ -z "$TAG_TAR_SHA" ]]; then
  echo "Fetching tag source tar.gz sha256..."
  TAG_TAR_SHA="$(fetch_sha "$SRC_TAR_URL")"
fi
if [[ -z "$TAG_ZIP_SHA" ]]; then
  echo "Fetching tag source zip sha256..."
  TAG_ZIP_SHA="$(fetch_sha "$SRC_ZIP_URL")"
fi
TAG_TAR_SHA="$(printf '%s' "$TAG_TAR_SHA" | tr '[:upper:]' '[:lower:]')"
TAG_ZIP_SHA="$(printf '%s' "$TAG_ZIP_SHA" | tr '[:upper:]' '[:lower:]')"
[[ "$TAG_TAR_SHA" =~ ^[0-9a-f]{64}$ ]] || {
  echo "error: tag tar sha256 must be 64 hex chars" >&2
  exit 1
}
[[ "$TAG_ZIP_SHA" =~ ^[0-9a-f]{64}$ ]] || {
  echo "error: tag zip sha256 must be 64 hex chars" >&2
  exit 1
}
if [[ "$TAG_TAR_SHA" =~ ^0{64}$ || "$TAG_ZIP_SHA" =~ ^0{64}$ ]]; then
  echo "error: refusing placeholder all-zero tag sha256" >&2
  exit 1
fi

echo "$VERSION" > VERSION
echo "Updated VERSION → $VERSION"

# --- Homebrew from-source Formula ---
python3 - "$VERSION" "$TAG_TAR_SHA" "$SRC_TAR_URL" <<'PY'
import re
import sys
from pathlib import Path

version, sha, url = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
path = Path("Formula/millennium-helpers.rb")
text = path.read_text(encoding="utf-8")
text = re.sub(r'url\s+"https://github\.com/[^"]+"', f'url "{url}"', text, count=1)
text = re.sub(r'sha256\s+"[0-9a-fA-F]{64}"', f'sha256 "{sha}"', text, count=1)
text = re.sub(r'^\s*version\s+"[^"]+"\n', '', text, count=1, flags=re.M)
path.write_text(text, encoding="utf-8")
print(f"Updated {path}")
PY

# --- Homebrew -bin Formula ---
python3 - "$VERSION" "$LINUX_SHA" "$TAG_URL_TGZ" <<'PY'
import re
import sys
from pathlib import Path

version, sha, url = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
path = Path("Formula/millennium-helpers-bin.rb")
text = path.read_text(encoding="utf-8")
text = re.sub(r'url\s+"https://github\.com/[^"]+"', f'url "{url}"', text, count=1)
text = re.sub(r'sha256\s+"[0-9a-fA-F]{64}"', f'sha256 "{sha}"', text, count=1)
text = re.sub(r'^\s*version\s+"[^"]+"\n', '', text, count=1, flags=re.M)
path.write_text(text, encoding="utf-8")
print(f"Updated {path}")
PY

# --- Scoop from-source (tag zip) ---
python3 - "$VERSION" "$TAG_ZIP_SHA" "$SRC_ZIP_URL" <<'PY'
import json
import sys
from pathlib import Path

version, sha, url = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
path = Path("packaging/scoop/millennium-helpers.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["version"] = version
data["url"] = url
data["hash"] = sha
data["extract_dir"] = f"millenium-helpers-{version}"
data["autoupdate"] = {
    "url": "https://github.com/bolens/millenium-helpers/archive/refs/tags/v$version.zip",
    "extract_dir": "millenium-helpers-$version",
}
path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

# --- Scoop -bin (Windows release zip) ---
python3 - "$VERSION" "$WINDOWS_SHA" "$TAG_URL_ZIP" <<'PY'
import json
import sys
from pathlib import Path

version, sha, url = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
path = Path("packaging/scoop/millennium-helpers-bin.json")
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

# --- Winget (bin / Windows zip only) ---
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
text = re.sub(r"(?m)^(\s*)InstallerUrl:\s*.*$", rf"\1InstallerUrl: {url}", text, count=1)
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

# --- Arch from-source PKGBUILD ---
python3 - "$VERSION" "$TAG_TAR_SHA" <<'PY'
import re
import sys
from pathlib import Path

version, sha = sys.argv[1], sys.argv[2].lower()
pkgbuild = Path("packaging/millennium-helpers/PKGBUILD")
text = pkgbuild.read_text(encoding="utf-8")
text = re.sub(r"(?m)^pkgver=.*$", f"pkgver={version}", text, count=1)
text = re.sub(r"(?m)^pkgrel=.*$", "pkgrel=1", text, count=1)
text = re.sub(
    r"(?m)^(sha256sums=\(')[0-9a-fA-F]{64}(')",
    rf"\g<1>{sha}\g<2>",
    text,
    count=1,
)
pkgbuild.write_text(text, encoding="utf-8")
print(f"Updated {pkgbuild}")
PY

# --- Arch -bin PKGBUILD ---
python3 - "$VERSION" "$LINUX_SHA" <<'PY'
import re
import sys
from pathlib import Path

version, sha = sys.argv[1], sys.argv[2].lower()
pkgbuild = Path("packaging/millennium-helpers-bin/PKGBUILD")
text = pkgbuild.read_text(encoding="utf-8")
text = re.sub(r"(?m)^pkgver=.*$", f"pkgver={version}", text, count=1)
text = re.sub(r"(?m)^pkgrel=.*$", "pkgrel=1", text, count=1)
text = re.sub(
    r"(?m)^(sha256sums=\(')[0-9a-fA-F]{64}(')",
    rf"\g<1>{sha}\g<2>",
    text,
    count=1,
)
pkgbuild.write_text(text, encoding="utf-8")
print(f"Updated {pkgbuild}")
PY

bash scripts/ci/sync-stable-srcinfo.sh
bash scripts/ci/sync-bin-srcinfo.sh

# --- Nix release-info.nix ---
python3 - "$VERSION" "$LINUX_SHA" "$TAG_TAR_SHA" <<'PY'
import base64
import binascii
import re
import sys
from pathlib import Path

version, linux_sha, tag_sha = sys.argv[1], sys.argv[2].lower(), sys.argv[3].lower()
asset_sri = "sha256-" + base64.b64encode(binascii.unhexlify(linux_sha)).decode("ascii")
git_sri = "sha256-" + base64.b64encode(binascii.unhexlify(tag_sha)).decode("ascii")
path = Path("nix/release-info.nix")
text = path.read_text(encoding="utf-8")
text = re.sub(r'(?m)^(\s*version\s*=\s*")[^"]*(";)', rf"\g<1>{version}\g<2>", text, count=1)
text = re.sub(r'(?m)^(\s*srcAssetHash\s*=\s*")[^"]*(";)', rf"\g<1>{asset_sri}\g<2>", text, count=1)
text = re.sub(r'(?m)^(\s*srcHash\s*=\s*")[^"]*(";)', rf"\g<1>{asset_sri}\g<2>", text, count=1)
text = re.sub(r'(?m)^(\s*srcGitHash\s*=\s*")[^"]*(";)', rf"\g<1>{git_sri}\g<2>", text, count=1)
path.write_text(text, encoding="utf-8")
print(f"Updated {path}")
PY

# --- deb / rpm / Chocolatey version pins ---
python3 - "$VERSION" "$LINUX_SHA" "$WINDOWS_SHA" "$TAG_TAR_SHA" <<'PY'
import re
import sys
from pathlib import Path

version, linux_sha, windows_sha, tag_sha = (
    sys.argv[1],
    sys.argv[2].lower(),
    sys.argv[3].lower(),
    sys.argv[4].lower(),
)

def bump_control(path: Path, ver: str) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^Version:\s*.*$", f"Version: {ver}", text, count=1)
    path.write_text(text, encoding="utf-8")
    print(f"Updated {path}")

def bump_spec(path: Path, ver: str, sha=None) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^Version:\s*.*$", f"Version: {ver}", text, count=1)
    text = re.sub(r"(?m)^Release:\s*.*$", "Release: 1%{?dist}", text, count=1)
    if sha:
        text = re.sub(
            r"(?m)^(Source0 sha256:\s*)[0-9a-fA-F]{64}\s*$",
            rf"\g<1>{sha}",
            text,
            count=1,
        )
        # Also support "%global source_sha256 ..." style
        text = re.sub(
            r"(?m)^(%global\s+source_sha256\s+)[0-9a-fA-F]{64}\s*$",
            rf"\g<1>{sha}",
            text,
            count=1,
        )
    path.write_text(text, encoding="utf-8")
    print(f"Updated {path}")

def bump_nuspec(path: Path, ver: str) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    text = re.sub(
        r"<version>[^<]+</version>",
        f"<version>{ver}</version>",
        text,
        count=1,
    )
    path.write_text(text, encoding="utf-8")
    print(f"Updated {path}")

def bump_choco_install(path: Path, ver: str, sha: str) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    text = re.sub(
        r"(\$version\s*=\s*')[^']+(')",
        rf"\g<1>{ver}\g<2>",
        text,
        count=1,
    )
    text = re.sub(
        r"(\$checksum\s*=\s*')[0-9a-fA-F]{64}(')",
        rf"\g<1>{sha}\g<2>",
        text,
        count=1,
    )
    path.write_text(text, encoding="utf-8")
    print(f"Updated {path}")

bump_control(Path("packaging/deb/millennium-helpers/DEBIAN/control"), version)
bump_control(Path("packaging/deb/millennium-helpers-bin/DEBIAN/control"), version)
bump_spec(Path("packaging/rpm/millennium-helpers.spec"), version, tag_sha)
bump_spec(Path("packaging/rpm/millennium-helpers-bin.spec"), version, linux_sha)
bump_nuspec(Path("packaging/chocolatey/millennium-helpers/millennium-helpers.nuspec"), version)
bump_choco_install(
    Path("packaging/chocolatey/millennium-helpers/tools/chocolateyInstall.ps1"),
    version,
    windows_sha,
)
PY

# Verify written manifests
python3 - "$VERSION" "$LINUX_SHA" "$WINDOWS_SHA" "$TAG_TAR_SHA" "$TAG_ZIP_SHA" <<'PY'
import base64
import binascii
import json
import re
import sys
from pathlib import Path

version, linux_sha, windows_sha, tag_tar, tag_zip = (
    sys.argv[1],
    sys.argv[2].lower(),
    sys.argv[3].lower(),
    sys.argv[4].lower(),
    sys.argv[5].lower(),
)
errors: list[str] = []

formula = Path("Formula/millennium-helpers.rb").read_text(encoding="utf-8")
if f'sha256 "{tag_tar}"' not in formula:
    errors.append("Formula/millennium-helpers.rb missing tag archive sha256")
if f"archive/refs/tags/v{version}.tar.gz" not in formula:
    errors.append("Formula/millennium-helpers.rb missing tag archive URL")

formula_bin = Path("Formula/millennium-helpers-bin.rb").read_text(encoding="utf-8")
if f'sha256 "{linux_sha}"' not in formula_bin:
    errors.append("Formula-bin missing linux sha256")
if f"releases/download/v{version}/millennium-helpers-linux.tar.gz" not in formula_bin:
    errors.append("Formula-bin missing release asset URL")

scoop = json.loads(Path("packaging/scoop/millennium-helpers.json").read_text(encoding="utf-8"))
if scoop.get("version") != version or str(scoop.get("hash", "")).lower() != tag_zip:
    errors.append("Scoop from-source version/hash mismatch")

scoop_bin = json.loads(Path("packaging/scoop/millennium-helpers-bin.json").read_text(encoding="utf-8"))
if scoop_bin.get("version") != version or str(scoop_bin.get("hash", "")).lower() != windows_sha:
    errors.append("Scoop-bin version/hash mismatch")

pkg = Path("packaging/millennium-helpers/PKGBUILD").read_text(encoding="utf-8")
if tag_tar not in pkg or not re.search(rf"(?m)^pkgver={re.escape(version)}$", pkg):
    errors.append("Arch from-source PKGBUILD mismatch")

pkg_bin = Path("packaging/millennium-helpers-bin/PKGBUILD").read_text(encoding="utf-8")
if linux_sha not in pkg_bin or not re.search(rf"(?m)^pkgver={re.escape(version)}$", pkg_bin):
    errors.append("Arch -bin PKGBUILD mismatch")

release_info = Path("nix/release-info.nix").read_text(encoding="utf-8")
asset_sri = "sha256-" + base64.b64encode(binascii.unhexlify(linux_sha)).decode("ascii")
git_sri = "sha256-" + base64.b64encode(binascii.unhexlify(tag_tar)).decode("ascii")
if f'srcAssetHash = "{asset_sri}"' not in release_info:
    errors.append("nix srcAssetHash mismatch")
if f'srcGitHash = "{git_sri}"' not in release_info:
    errors.append("nix srcGitHash mismatch")

if Path("VERSION").read_text(encoding="utf-8").strip() != version:
    errors.append("VERSION file mismatch")

if errors:
    for err in errors:
        print(f"error: {err}", file=sys.stderr)
    raise SystemExit(1)
print("Verified packaging hashes and versions after update.")
PY

echo "Packaging files updated for v${VERSION} (from-source + bin matrix)."
