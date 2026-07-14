#!/usr/bin/env bash
# Update Formula / Scoop / Winget / Arch / Nix / deb / rpm / Chocolatey for a release tag.
# Usage:
#   update-packaging-versions.sh <version> <linux_amd64_sha> <windows_amd64_sha> [repo] \
#     [src_tar_sha] [src_zip_sha] [darwin_amd64_sha] [darwin_arm64_sha] [linux_arm64_sha]
#
#   version: semver without leading v (e.g. 2.2.0)
#   linux_amd64_sha / windows_amd64_sha: primary bin packs
#   src_* : controlled -src.tar.gz / -src.zip (fetched from draft release if omitted)
#   darwin_* / linux_arm64_sha: Homebrew-bin OS/arch packs (default to linux_amd64 if omitted)
#
# Matrix:
#   from-source → Formula, Scoop plain, Arch, Nix srcGitHash (via -src archives)
#   bin         → Formula-bin (multi-arch), Scoop-bin, Arch-bin, Winget, Nix, Chocolatey, deb/rpm-bin
#   git         → not updated here
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/lib/release_assets.sh
source "$ROOT/scripts/lib/release_assets.sh"

VERSION="${1:?version required (e.g. 2.2.0)}"
LINUX_SHA="${2:?linux-amd64 release-asset sha256 required}"
WINDOWS_SHA="${3:?windows-amd64 release-asset sha256 required}"
REPO="${4:-bolens/millenium-helpers}"
SRC_TAR_SHA="${5:-}"
SRC_ZIP_SHA="${6:-}"
DARWIN_AMD64_SHA="${7:-}"
DARWIN_ARM64_SHA="${8:-}"
LINUX_ARM64_SHA="${9:-}"

VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]] || {
  echo "error: invalid version '$VERSION'" >&2
  exit 1
}

normalize_sha() {
  local label="$1" sha="$2"
  sha="$(printf '%s' "$sha" | tr '[:upper:]' '[:lower:]')"
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || {
    echo "error: ${label} sha256 must be 64 hex chars" >&2
    exit 1
  }
  if [[ "$sha" =~ ^0{64}$ ]]; then
    echo "error: refusing placeholder all-zero ${label} sha256" >&2
    exit 1
  fi
  printf '%s' "$sha"
}

LINUX_SHA="$(normalize_sha linux-amd64 "$LINUX_SHA")"
WINDOWS_SHA="$(normalize_sha windows-amd64 "$WINDOWS_SHA")"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo "error: repo must look like owner/name (got '$REPO')" >&2
  exit 1
}

ASSET_LINUX_AMD64="$(release_asset_helpers "$VERSION" linux amd64 tar.gz)"
ASSET_LINUX_ARM64="$(release_asset_helpers "$VERSION" linux arm64 tar.gz)"
ASSET_DARWIN_AMD64="$(release_asset_helpers "$VERSION" darwin amd64 tar.gz)"
ASSET_DARWIN_ARM64="$(release_asset_helpers "$VERSION" darwin arm64 tar.gz)"
ASSET_WINDOWS="$(release_asset_helpers "$VERSION" windows amd64 zip)"
ASSET_SRC_TAR="$(release_asset_src "$VERSION" tar.gz)"
ASSET_SRC_ZIP="$(release_asset_src "$VERSION" zip)"

URL_LINUX_AMD64="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_LINUX_AMD64}"
URL_LINUX_ARM64="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_LINUX_ARM64}"
URL_DARWIN_AMD64="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_DARWIN_AMD64}"
URL_DARWIN_ARM64="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_DARWIN_ARM64}"
URL_WINDOWS="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_WINDOWS}"
URL_SRC_TAR="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_SRC_TAR}"
URL_SRC_ZIP="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_SRC_ZIP}"
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

if [[ -z "$SRC_TAR_SHA" ]]; then
  echo "Fetching ${ASSET_SRC_TAR} sha256..."
  SRC_TAR_SHA="$(fetch_sha "$URL_SRC_TAR")"
fi
if [[ -z "$SRC_ZIP_SHA" ]]; then
  echo "Fetching ${ASSET_SRC_ZIP} sha256..."
  SRC_ZIP_SHA="$(fetch_sha "$URL_SRC_ZIP")"
fi
SRC_TAR_SHA="$(normalize_sha src-tar "$SRC_TAR_SHA")"
SRC_ZIP_SHA="$(normalize_sha src-zip "$SRC_ZIP_SHA")"

DARWIN_AMD64_SHA="$(normalize_sha darwin-amd64 "${DARWIN_AMD64_SHA:-$LINUX_SHA}")"
DARWIN_ARM64_SHA="$(normalize_sha darwin-arm64 "${DARWIN_ARM64_SHA:-$LINUX_SHA}")"
LINUX_ARM64_SHA="$(normalize_sha linux-arm64 "${LINUX_ARM64_SHA:-$LINUX_SHA}")"

echo "$VERSION" > VERSION
echo "Updated VERSION → $VERSION"

# --- Homebrew from-source Formula ---
python3 - "$VERSION" "$SRC_TAR_SHA" "$URL_SRC_TAR" <<'PY'
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

# --- Homebrew -bin Formula (multi OS/arch) ---
python3 - \
  "$VERSION" \
  "$URL_DARWIN_ARM64" "$DARWIN_ARM64_SHA" \
  "$URL_DARWIN_AMD64" "$DARWIN_AMD64_SHA" \
  "$URL_LINUX_ARM64" "$LINUX_ARM64_SHA" \
  "$URL_LINUX_AMD64" "$LINUX_SHA" <<'PY'
import re
import sys
from pathlib import Path

(
    version,
    url_d_arm, sha_d_arm,
    url_d_amd, sha_d_amd,
    url_l_arm, sha_l_arm,
    url_l_amd, sha_l_amd,
) = sys.argv[1:]
sha_d_arm = sha_d_arm.lower()
sha_d_amd = sha_d_amd.lower()
sha_l_arm = sha_l_arm.lower()
sha_l_amd = sha_l_amd.lower()

path = Path("Formula/millennium-helpers-bin.rb")
text = path.read_text(encoding="utf-8")

# Replace the four on_* url/sha256 pairs in file order: darwin-arm, darwin-intel, linux-arm, linux-intel
pairs = [
    (url_d_arm, sha_d_arm),
    (url_d_amd, sha_d_amd),
    (url_l_arm, sha_l_arm),
    (url_l_amd, sha_l_amd),
]
idx = 0
parts: list[str] = []
pos = 0
pattern = re.compile(
    r'url\s+"https://github\.com/[^"]+"\s*\n\s*sha256\s+"[0-9a-fA-F]{64}"'
)
for m in pattern.finditer(text):
    if idx >= len(pairs):
        break
    url, sha = pairs[idx]
    idx += 1
    parts.append(text[pos:m.start()])
    indent_url = re.match(r'(\s*)url', m.group(0))
    indent = indent_url.group(1) if indent_url else "      "
    parts.append(f'{indent}url "{url}"\n{indent}sha256 "{sha}"')
    pos = m.end()
parts.append(text[pos:])
if idx != len(pairs):
    raise SystemExit(f"error: expected {len(pairs)} url/sha256 pairs in Formula-bin, found {idx}")
path.write_text("".join(parts), encoding="utf-8")
print(f"Updated {path}")
PY

# --- Scoop from-source (-src.zip) ---
python3 - "$VERSION" "$SRC_ZIP_SHA" "$URL_SRC_ZIP" "$ASSET_SRC_ZIP" <<'PY'
import json
import sys
from pathlib import Path

version, sha, url, asset = sys.argv[1], sys.argv[2].lower(), sys.argv[3], sys.argv[4]
path = Path("packaging/scoop/millennium-helpers.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["version"] = version
data["url"] = url
data["hash"] = sha
data["extract_dir"] = f"millenium-helpers-{version}"
data["autoupdate"] = {
    "url": f"https://github.com/bolens/millenium-helpers/releases/download/v$version/millennium-helpers-v$version-src.zip",
    "extract_dir": "millenium-helpers-$version",
}
path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

# --- Scoop -bin (Windows release zip) ---
python3 - "$VERSION" "$WINDOWS_SHA" "$URL_WINDOWS" "$ASSET_WINDOWS" <<'PY'
import json
import sys
from pathlib import Path

version, sha, url, asset = sys.argv[1], sys.argv[2].lower(), sys.argv[3], sys.argv[4]
path = Path("packaging/scoop/millennium-helpers-bin.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["version"] = version
data["url"] = url
data["hash"] = sha
data["autoupdate"] = {
    "url": f"https://github.com/bolens/millenium-helpers/releases/download/v$version/millennium-helpers-v$version-windows-amd64.zip",
    "hash": {
        "url": f"https://github.com/bolens/millenium-helpers/releases/download/v$version/millennium-helpers-v$version-windows-amd64.zip.sha256"
    },
}
path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY

# --- Winget (bin / Windows zip only) ---
python3 - "$VERSION" "$WINDOWS_SHA" "$URL_WINDOWS" "$TODAY" <<'PY'
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
python3 - "$VERSION" "$SRC_TAR_SHA" <<'PY'
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
python3 - "$VERSION" "$LINUX_SHA" "$SRC_TAR_SHA" <<'PY'
import base64
import binascii
import re
import sys
from pathlib import Path

version, linux_sha, src_sha = sys.argv[1], sys.argv[2].lower(), sys.argv[3].lower()
asset_sri = "sha256-" + base64.b64encode(binascii.unhexlify(linux_sha)).decode("ascii")
git_sri = "sha256-" + base64.b64encode(binascii.unhexlify(src_sha)).decode("ascii")
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
python3 - "$VERSION" "$LINUX_SHA" "$WINDOWS_SHA" "$SRC_TAR_SHA" <<'PY'
import re
import sys
from pathlib import Path

version, linux_sha, windows_sha, src_sha = (
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

def bump_page_path(path: Path, ver: str, sha: str) -> None:
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
bump_spec(Path("packaging/rpm/millennium-helpers.spec"), version, src_sha)
bump_spec(Path("packaging/rpm/millennium-helpers-bin.spec"), version, linux_sha)
bump_nuspec(Path("packaging/chocolatey/millennium-helpers/millennium-helpers.nuspec"), version)
bump_page_path(
    Path("packaging/chocolatey/millennium-helpers/tools/chocolateyInstall.ps1"),
    version,
    windows_sha,
)
PY

# Verify written manifests
python3 - "$VERSION" "$LINUX_SHA" "$WINDOWS_SHA" "$SRC_TAR_SHA" "$SRC_ZIP_SHA" \
  "$ASSET_LINUX_AMD64" "$ASSET_WINDOWS" "$ASSET_SRC_TAR" "$ASSET_SRC_ZIP" <<'PY'
import base64
import binascii
import json
import re
import sys
from pathlib import Path

(
    version,
    linux_sha,
    windows_sha,
    src_tar,
    src_zip,
    asset_linux,
    asset_windows,
    asset_src_tar,
    asset_src_zip,
) = sys.argv[1:]
linux_sha = linux_sha.lower()
windows_sha = windows_sha.lower()
src_tar = src_tar.lower()
src_zip = src_zip.lower()
errors: list[str] = []

formula = Path("Formula/millennium-helpers.rb").read_text(encoding="utf-8")
if f'sha256 "{src_tar}"' not in formula:
    errors.append("Formula/millennium-helpers.rb missing src archive sha256")
if f"releases/download/v{version}/{asset_src_tar}" not in formula:
    errors.append("Formula/millennium-helpers.rb missing -src.tar.gz URL")

formula_bin = Path("Formula/millennium-helpers-bin.rb").read_text(encoding="utf-8")
if f"releases/download/v{version}/{asset_linux}" not in formula_bin:
    errors.append("Formula-bin missing linux-amd64 release asset URL")
if f'sha256 "{linux_sha}"' not in formula_bin:
    errors.append("Formula-bin missing linux-amd64 sha256")

scoop = json.loads(Path("packaging/scoop/millennium-helpers.json").read_text(encoding="utf-8"))
if scoop.get("version") != version or str(scoop.get("hash", "")).lower() != src_zip:
    errors.append("Scoop from-source version/hash mismatch")
if asset_src_zip not in str(scoop.get("url", "")):
    errors.append("Scoop from-source URL must use -src.zip")

scoop_bin = json.loads(Path("packaging/scoop/millennium-helpers-bin.json").read_text(encoding="utf-8"))
if scoop_bin.get("version") != version or str(scoop_bin.get("hash", "")).lower() != windows_sha:
    errors.append("Scoop-bin version/hash mismatch")
if asset_windows not in str(scoop_bin.get("url", "")):
    errors.append("Scoop-bin URL must use windows-amd64 zip")

pkg = Path("packaging/millennium-helpers/PKGBUILD").read_text(encoding="utf-8")
if src_tar not in pkg or not re.search(rf"(?m)^pkgver={re.escape(version)}$", pkg):
    errors.append("Arch from-source PKGBUILD mismatch")
if f"millennium-helpers-v${{pkgver}}-src.tar.gz" not in pkg and asset_src_tar not in pkg:
    errors.append("Arch from-source PKGBUILD missing -src.tar.gz")

pkg_bin = Path("packaging/millennium-helpers-bin/PKGBUILD").read_text(encoding="utf-8")
if linux_sha not in pkg_bin or not re.search(rf"(?m)^pkgver={re.escape(version)}$", pkg_bin):
    errors.append("Arch -bin PKGBUILD mismatch")

release_info = Path("nix/release-info.nix").read_text(encoding="utf-8")
asset_sri = "sha256-" + base64.b64encode(binascii.unhexlify(linux_sha)).decode("ascii")
git_sri = "sha256-" + base64.b64encode(binascii.unhexlify(src_tar)).decode("ascii")
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
