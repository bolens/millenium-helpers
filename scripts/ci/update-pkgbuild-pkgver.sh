#!/usr/bin/env bash
# Sync packaging/PKGBUILD pkgver and .SRCINFO from the current git HEAD.
# Does not build or install — use this instead of makepkg -si just to bump pkgver.
#
# Usage:
#   scripts/ci/update-pkgbuild-pkgver.sh
#   make sync-pkgver
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKGBUILD="${ROOT}/packaging/PKGBUILD"
SRCINFO="${ROOT}/packaging/.SRCINFO"

cd "$ROOT"

[[ -f "$PKGBUILD" ]] || {
  echo "error: missing $PKGBUILD" >&2
  exit 1
}

# Same formula as packaging/PKGBUILD pkgver()
newver="$(printf 'r%s.g%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)")"
oldver="$(grep -E '^pkgver=' "$PKGBUILD" | head -1 | cut -d= -f2-)"

if [[ "$oldver" != "$newver" ]]; then
  # Arch convention: reset pkgrel when pkgver changes
  sed -i \
    -e "s/^pkgver=.*/pkgver=${newver}/" \
    -e "s/^pkgrel=.*/pkgrel=1/" \
    "$PKGBUILD"
  echo "Updated pkgver: ${oldver} → ${newver} (pkgrel=1)"
else
  echo "pkgver already ${newver}"
fi

# Prefer a full .SRCINFO regenerate via makepkg when safe (not root).
# Otherwise patch pkgver/pkgrel in place so this still works without makepkg.
if command -v makepkg >/dev/null 2>&1 && [[ "$(id -u)" -ne 0 ]]; then
  (cd "${ROOT}/packaging" && makepkg --printsrcinfo > .SRCINFO)
  echo "Regenerated packaging/.SRCINFO via makepkg --printsrcinfo"
elif [[ -f "$SRCINFO" ]]; then
  sed -i \
    -e "s/^\tpkgver = .*/\tpkgver = ${newver}/" \
    -e "s/^\tpkgrel = .*/\tpkgrel = 1/" \
    "$SRCINFO"
  echo "Patched packaging/.SRCINFO pkgver=${newver} pkgrel=1"
else
  echo "error: packaging/.SRCINFO missing and makepkg unavailable/unusable" >&2
  exit 1
fi
