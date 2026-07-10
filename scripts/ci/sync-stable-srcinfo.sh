#!/usr/bin/env bash
# Sync packaging/millennium-helpers/.SRCINFO from PKGBUILD.
# Prefer makepkg --printsrcinfo; fall back to patching key fields when makepkg
# is unavailable (non-Arch hosts / root).
#
# Usage:
#   scripts/ci/sync-stable-srcinfo.sh           # write .SRCINFO
#   scripts/ci/sync-stable-srcinfo.sh --check   # exit 1 if stale (no writes)
#   make sync-stable-srcinfo
#
# Prefer make bump-version for full pre-tag bumps (calls this automatically).
# See CONTRIBUTING.md § Versioning.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PKG_DIR="packaging/millennium-helpers"
PKGBUILD="${PKG_DIR}/PKGBUILD"
SRCINFO="${PKG_DIR}/.SRCINFO"
CHECK_ONLY=0

if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

[[ -f "$PKGBUILD" ]] || {
  echo "error: missing $PKGBUILD" >&2
  exit 1
}

pkgver="$(grep -E '^pkgver=' "$PKGBUILD" | head -1 | cut -d= -f2-)"
pkgrel="$(grep -E '^pkgrel=' "$PKGBUILD" | head -1 | cut -d= -f2-)"
[[ -n "$pkgver" && -n "$pkgrel" ]] || {
  echo "error: could not parse pkgver/pkgrel from $PKGBUILD" >&2
  exit 1
}

# First sha256sums entry is the Linux release tarball.
tarball_sha="$(python3 - "$PKGBUILD" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"(?m)^sha256sums=\('([0-9a-fA-F]{64})'", text)
print(m.group(1).lower() if m else "")
PY
)"

expected_source="https://github.com/bolens/millenium-helpers/releases/download/v${pkgver}/millennium-helpers-linux.tar.gz"

srcinfo_stale() {
  [[ -f "$SRCINFO" ]] || return 0
  local info
  info="$(cat "$SRCINFO")"
  grep -qE "^[[:space:]]*pkgver = ${pkgver}$" <<<"$info" || return 0
  grep -qE "^[[:space:]]*pkgrel = ${pkgrel}$" <<<"$info" || return 0
  grep -qF "source = ${expected_source}" <<<"$info" || return 0
  if [[ -n "$tarball_sha" ]]; then
    grep -qE "^[[:space:]]*sha256sums = ${tarball_sha}$" <<<"$info" || return 0
  fi
  return 1
}

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  if srcinfo_stale; then
    echo "error: ${SRCINFO} is out of date with ${PKGBUILD}" >&2
    echo "Run: bash scripts/ci/sync-stable-srcinfo.sh && git add ${SRCINFO}" >&2
    exit 1
  fi
  echo "stable .SRCINFO OK (pkgver=${pkgver})"
  exit 0
fi

write_via_makepkg() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 1
  fi
  command -v makepkg >/dev/null 2>&1 || return 1
  # Write to a temp file first so a failed makepkg never truncates .SRCINFO.
  # PKGBUILD may reference install=… / source files that must exist beside it.
  local tmp
  tmp="$(mktemp "${PKG_DIR}/.SRCINFO.tmp.XXXXXX")"
  if ! (cd "$PKG_DIR" && makepkg --printsrcinfo >"$(basename "$tmp")"); then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$SRCINFO"
}

write_via_patch() {
  [[ -f "$SRCINFO" ]] || {
    echo "error: ${SRCINFO} missing and makepkg unavailable" >&2
    exit 1
  }
  python3 - "$SRCINFO" "$pkgver" "$pkgrel" "$expected_source" "$tarball_sha" <<'PY'
import re
import sys
from pathlib import Path

path, pkgver, pkgrel, source, sha = sys.argv[1:6]
info = Path(path).read_text(encoding="utf-8")
info = re.sub(r"(?m)^(\tpkgver = ).*$", rf"\g<1>{pkgver}", info, count=1)
info = re.sub(r"(?m)^(\tpkgrel = ).*$", rf"\g<1>{pkgrel}", info, count=1)
info = re.sub(
    r"(?m)^(\tsource = https://github\.com/.+/releases/download/)v[^/]+(/millennium-helpers-linux\.tar\.gz)$",
    rf"\g<1>v{pkgver}\g<2>",
    info,
    count=1,
)
if sha:
    info = re.sub(
        r"(?m)^(\tsha256sums = )[0-9a-fA-F]{64}$",
        rf"\g<1>{sha}",
        info,
        count=1,
    )
Path(path).write_text(info, encoding="utf-8")
PY
}

before=""
[[ -f "$SRCINFO" ]] && before="$(cat "$SRCINFO")"

if write_via_makepkg; then
  echo "Regenerated ${SRCINFO} via makepkg --printsrcinfo"
else
  write_via_patch
  echo "Patched ${SRCINFO} (makepkg unavailable)"
fi

after="$(cat "$SRCINFO")"
if [[ "$before" != "$after" ]]; then
  # Pre-commit: abort so the user re-stages (same pattern as sync-git-srcinfo).
  if [[ -n "${PRE_COMMIT:-}" ]]; then
    echo "${SRCINFO} updated — re-stage it and retry the commit." >&2
    exit 1
  fi
fi
