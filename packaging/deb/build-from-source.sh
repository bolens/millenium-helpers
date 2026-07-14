#!/usr/bin/env bash
# Build a .deb from a tag checkout / source tree (millennium-helpers from-source).
# Usage: packaging/deb/build-from-source.sh [version]
# Requires: go, make, dpkg-deb. Run from a source tree that can `make build`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
VERSION="${VERSION#v}"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cd "$ROOT"
export CGO_ENABLED=0
make build

DEST="$STAGE/root"
install -d "$DEST/usr/bin" "$DEST/usr/lib/millennium-helpers/lib" \
  "$DEST/usr/share/bash-completion/completions" \
  "$DEST/usr/share/zsh/site-functions" \
  "$DEST/usr/share/fish/vendor_completions.d" \
  "$DEST/usr/share/nushell/completions" \
  "$DEST/usr/share/man/man1" \
  "$DEST/usr/share/doc/millennium-helpers" \
  "$DEST/DEBIAN"

# Long-name PATH entries are argv0 twins of the Go dispatcher.
for twin in millennium millennium-mcp millennium-repair millennium-upgrade \
  millennium-schedule millennium-purge millennium-diag millennium-theme
do
  install -m755 bin/millennium "$DEST/usr/bin/$twin"
done

install -m644 scripts/common.sh "$DEST/usr/lib/millennium-helpers/common.sh"
install -m644 scripts/lib/*.sh "$DEST/usr/lib/millennium-helpers/lib/"
install -m644 VERSION "$DEST/usr/lib/millennium-helpers/VERSION"
install -m644 completions/bash/millennium-helpers "$DEST/usr/share/bash-completion/completions/millennium-helpers"
for s in millennium millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp; do
  ln -sf millennium-helpers "$DEST/usr/share/bash-completion/completions/$s"
done
install -m644 completions/zsh/_millennium-helpers "$DEST/usr/share/zsh/site-functions/_millennium-helpers"
for s in millennium millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp; do
  ln -sf _millennium-helpers "$DEST/usr/share/zsh/site-functions/_$s"
done
install -m644 completions/fish/*.fish "$DEST/usr/share/fish/vendor_completions.d/"
install -m644 completions/nushell/millennium-helpers.nu "$DEST/usr/share/nushell/completions/"
install -m644 man/*.1 "$DEST/usr/share/man/man1/"
install -m644 LICENSE "$DEST/usr/share/doc/millennium-helpers/copyright"
[[ -f third_party/MILLENNIUM-LICENSE.md ]] && \
  install -m644 third_party/MILLENNIUM-LICENSE.md "$DEST/usr/lib/millennium-helpers/"

sed "s/^Version:.*/Version: ${VERSION}/" \
  "$ROOT/packaging/deb/millennium-helpers/DEBIAN/control" > "$DEST/DEBIAN/control"

mkdir -p "$OUT_DIR"
DEB="$OUT_DIR/millennium-helpers_${VERSION}_amd64.deb"
dpkg-deb --build --root-owner-group "$DEST" "$DEB"
echo "Wrote $DEB"
