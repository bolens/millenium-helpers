#!/usr/bin/env bash
# Build a .deb from the published Linux release tarball (millennium-helpers-bin).
# Usage: packaging/deb/build-bin.sh [version] [tarball path or URL]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
VERSION="${VERSION#v}"
SRC="${2:-https://github.com/bolens/millenium-helpers/releases/download/v${VERSION}/millennium-helpers-v${VERSION}-linux-amd64.tar.gz}"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

TGZ="$STAGE/src.tar.gz"
if [[ "$SRC" == http* ]]; then
  curl -fsSL "$SRC" -o "$TGZ"
else
  cp "$SRC" "$TGZ"
fi

mkdir -p "$STAGE/extract" "$STAGE/root"
tar -xzf "$TGZ" -C "$STAGE/extract"
# Release tarball is flat at extract root.
TREE="$STAGE/extract"
[[ -d "$TREE/scripts" ]] || TREE="$(find "$STAGE/extract" -mindepth 1 -maxdepth 1 -type d | head -1)"

DEST="$STAGE/root"
install -d "$DEST/usr/bin" "$DEST/usr/lib/millennium-helpers/lib" \
  "$DEST/usr/share/bash-completion/completions" \
  "$DEST/usr/share/zsh/site-functions" \
  "$DEST/usr/share/fish/vendor_completions.d" \
  "$DEST/usr/share/nushell/completions" \
  "$DEST/usr/share/man/man1" \
  "$DEST/usr/share/doc/millennium-helpers-bin" \
  "$DEST/DEBIAN"

if [[ ! -x "$TREE/bin/millennium" ]]; then
  echo "error: release tree missing bin/millennium (Go dispatcher required)" >&2
  exit 1
fi
# Long-name PATH entries are argv0 twins of the Go dispatcher.
for twin in millennium millennium-mcp millennium-repair millennium-upgrade \
  millennium-schedule millennium-purge millennium-diag millennium-theme
do
  install -m755 "$TREE/bin/millennium" "$DEST/usr/bin/$twin"
done

install -m644 "$TREE"/scripts/common.sh "$DEST/usr/lib/millennium-helpers/common.sh"
install -m644 "$TREE"/scripts/lib/*.sh "$DEST/usr/lib/millennium-helpers/lib/"
install -m644 "$TREE"/VERSION "$DEST/usr/lib/millennium-helpers/VERSION"
install -m644 "$TREE"/completions/bash/millennium-helpers "$DEST/usr/share/bash-completion/completions/millennium-helpers"
for s in millennium millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp; do
  ln -sf millennium-helpers "$DEST/usr/share/bash-completion/completions/$s"
done
install -m644 "$TREE"/completions/zsh/_millennium-helpers "$DEST/usr/share/zsh/site-functions/_millennium-helpers"
for s in millennium millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp; do
  ln -sf _millennium-helpers "$DEST/usr/share/zsh/site-functions/_$s"
done
install -m644 "$TREE"/completions/fish/*.fish "$DEST/usr/share/fish/vendor_completions.d/"
install -m644 "$TREE"/completions/nushell/millennium-helpers.nu "$DEST/usr/share/nushell/completions/"
install -m644 "$TREE"/man/*.1 "$DEST/usr/share/man/man1/"
install -m644 "$TREE"/LICENSE "$DEST/usr/share/doc/millennium-helpers-bin/copyright"
[[ -f "$TREE/third_party/MILLENNIUM-LICENSE.md" ]] && \
  install -m644 "$TREE/third_party/MILLENNIUM-LICENSE.md" "$DEST/usr/lib/millennium-helpers/"

sed "s/^Version:.*/Version: ${VERSION}/" \
  "$ROOT/packaging/deb/millennium-helpers-bin/DEBIAN/control" > "$DEST/DEBIAN/control"

mkdir -p "$OUT_DIR"
DEB="$OUT_DIR/millennium-helpers-bin_${VERSION}_amd64.deb"
dpkg-deb --build --root-owner-group "$DEST" "$DEB"
echo "Wrote $DEB"
