#!/usr/bin/env bash
# Sync packaging/millennium-helpers-git PKGBUILD pkgver and .SRCINFO from HEAD.
# Does not build or install — use this instead of makepkg -si just to bump pkgver.
#
# Usage:
#   scripts/ci/update-pkgbuild-pkgver.sh           # write pkgver for current HEAD
#   scripts/ci/update-pkgbuild-pkgver.sh --check   # exit 1 if stale (no writes)
#   make sync-pkgver
#
# Note: a commit cannot embed its own short SHA (amending changes the hash).
# Pre-commit runs this against HEAD *before* the new commit, so the committed
# pkgver matches the parent. `pkgver()` in the PKGBUILD still recalculates at
# makepkg time from the checkout tip.
#
# The versioned package (packaging/millennium-helpers/) is updated by release CD
# via update-packaging-versions.sh — not by this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT}/packaging/millennium-helpers-git"
PKGBUILD="${PKG_DIR}/PKGBUILD"
SRCINFO="${PKG_DIR}/.SRCINFO"

cd "$ROOT"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
fi

[[ -f "$PKGBUILD" ]] || {
  echo "error: missing $PKGBUILD" >&2
  exit 1
}

# Same formula as packaging/millennium-helpers-git/PKGBUILD pkgver()
newver="$(printf 'r%s.g%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)")"
oldver="$(grep -E '^pkgver=' "$PKGBUILD" | head -1 | cut -d= -f2-)"

if [[ "$CHECK_ONLY" == true ]]; then
  if [[ "$oldver" != "$newver" ]]; then
    echo "error: packaging/millennium-helpers-git/PKGBUILD pkgver is stale ($oldver ≠ $newver)" >&2
    echo "Run: make sync-pkgver && git add packaging/millennium-helpers-git/PKGBUILD packaging/millennium-helpers-git/.SRCINFO" >&2
    exit 1
  fi
  echo "pkgver OK ($newver)"
  exit 0
fi

changed=false
if [[ "$oldver" != "$newver" ]]; then
  # Arch convention: reset pkgrel when pkgver changes
  sed -i \
    -e "s/^pkgver=.*/pkgver=${newver}/" \
    -e "s/^pkgrel=.*/pkgrel=1/" \
    "$PKGBUILD"
  echo "Updated pkgver: ${oldver} → ${newver} (pkgrel=1)"
  changed=true
else
  echo "pkgver already ${newver}"
fi

# Prefer a full .SRCINFO regenerate via makepkg when safe (not root).
# Otherwise patch pkgver/pkgrel in place so this still works without makepkg.
if command -v makepkg >/dev/null 2>&1 && [[ "$(id -u)" -ne 0 ]]; then
  before_srcinfo=""
  [[ -f "$SRCINFO" ]] && before_srcinfo="$(cat "$SRCINFO")"
  (cd "$PKG_DIR" && makepkg --printsrcinfo > .SRCINFO)
  after_srcinfo="$(cat "$SRCINFO")"
  if [[ "$before_srcinfo" != "$after_srcinfo" ]]; then
    echo "Regenerated packaging/millennium-helpers-git/.SRCINFO via makepkg --printsrcinfo"
    changed=true
  else
    echo "packaging/millennium-helpers-git/.SRCINFO already up to date"
  fi
elif [[ -f "$SRCINFO" ]]; then
  before_srcinfo="$(cat "$SRCINFO")"
  sed -i \
    -e "s/^\tpkgver = .*/\tpkgver = ${newver}/" \
    -e "s/^\tpkgrel = .*/\tpkgrel = 1/" \
    "$SRCINFO"
  after_srcinfo="$(cat "$SRCINFO")"
  if [[ "$before_srcinfo" != "$after_srcinfo" ]]; then
    echo "Patched packaging/millennium-helpers-git/.SRCINFO pkgver=${newver} pkgrel=1"
    changed=true
  fi
else
  echo "error: packaging/millennium-helpers-git/.SRCINFO missing and makepkg unavailable/unusable" >&2
  exit 1
fi

# Under pre-commit: fail so the commit aborts and the user re-stages the updates.
if [[ "$changed" == true && -n "${PRE_COMMIT:-}" ]]; then
  echo "pkgver files updated — re-stage packaging/millennium-helpers-git/PKGBUILD packaging/millennium-helpers-git/.SRCINFO and retry the commit." >&2
  exit 1
fi
