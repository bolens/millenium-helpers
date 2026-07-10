#!/usr/bin/env bash
# Regenerate packaging/millennium-helpers-git/.SRCINFO from PKGBUILD.
#
# Arch/AUR VCS policy: do not bump -git pkgver on every upstream commit.
# pkgver() recalculates at makepkg time. Only refresh .SRCINFO when the
# packaging recipe changes (deps, sources, install script, etc.).
#
# Usage:
#   scripts/ci/sync-git-srcinfo.sh           # write .SRCINFO
#   scripts/ci/sync-git-srcinfo.sh --check   # exit 1 if stale (ignores pkgver drift)
#   make sync-git-srcinfo
#
# See CONTRIBUTING.md § Versioning.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PKG_DIR="packaging/millennium-helpers-git"
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

can_makepkg() {
  [[ "$(id -u)" -ne 0 ]] && command -v makepkg >/dev/null 2>&1
}

printsrcinfo_to() {
  local out="$1"
  (cd "$PKG_DIR" && makepkg --printsrcinfo >"$(basename "$out")")
}

# Compare committed .SRCINFO to generated, ignoring pkgver (VCS packages drift by design).
srcinfo_recipe_stale() {
  [[ -f "$SRCINFO" ]] || return 0
  can_makepkg || {
    echo "warning: makepkg unavailable; skipping -git .SRCINFO check" >&2
    return 1
  }
  local tmp
  tmp="$(mktemp "${PKG_DIR}/.SRCINFO.check.XXXXXX")"
  if ! printsrcinfo_to "$tmp"; then
    rm -f "$tmp"
    echo "error: makepkg --printsrcinfo failed for ${PKG_DIR}" >&2
    return 0
  fi
  if diff -u -I '[[:space:]]*pkgver =' "$SRCINFO" "$tmp" >/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  diff -u -I '[[:space:]]*pkgver =' "$SRCINFO" "$tmp" >&2 || true
  rm -f "$tmp"
  return 0
}

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  if srcinfo_recipe_stale; then
    echo "error: ${SRCINFO} is out of date with ${PKGBUILD} (non-pkgver fields)" >&2
    echo "Run: make sync-git-srcinfo && git add ${SRCINFO}" >&2
    exit 1
  fi
  echo "git .SRCINFO OK (pkgver drift ignored; pkgver() is authoritative at build time)"
  exit 0
fi

if ! can_makepkg; then
  echo "warning: makepkg unavailable; not regenerating ${SRCINFO}" >&2
  echo "On Arch: make sync-git-srcinfo" >&2
  exit 0
fi

before=""
[[ -f "$SRCINFO" ]] && before="$(cat "$SRCINFO")"

tmp="$(mktemp "${PKG_DIR}/.SRCINFO.tmp.XXXXXX")"
if ! printsrcinfo_to "$tmp"; then
  rm -f "$tmp"
  echo "error: makepkg --printsrcinfo failed for ${PKG_DIR}" >&2
  exit 1
fi
mv -f "$tmp" "$SRCINFO"
echo "Regenerated ${SRCINFO} via makepkg --printsrcinfo"

after="$(cat "$SRCINFO")"
if [[ "$before" != "$after" && -n "${PRE_COMMIT:-}" ]]; then
  echo "${SRCINFO} updated — re-stage it and retry the commit." >&2
  exit 1
fi
