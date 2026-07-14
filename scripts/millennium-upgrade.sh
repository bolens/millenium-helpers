#!/usr/bin/env bash
# Install official Millennium releases — thin-wrap to Go.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install official Millennium (stable, beta, or main) releases.

Options:
  -c, --channel CHANNEL  Update channel: stable, beta, or main
  --stable|--beta|--main
  -r, --rollback [ID]    Roll back (or pass "list")
  --file PATH            Install from a local archive
  --sha256 HEX           Expected SHA256 of --file
  --insecure-skip-verify Allow --file without checksum
  --all-users            Linux/macOS multi-user hooks
  -f, --force  -y, --yes  -d, --dry-run  -q, --quiet
  -V, --version  -h, --help
EOF
}

resolve_millennium_go() {
  local cand
  for cand in \
    "${SCRIPT_DIR}/../bin/millennium" \
    "${SCRIPT_DIR}/millennium" \
    "$(command -v millennium 2>/dev/null || true)"
  do
    if [[ -n "$cand" && -x "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

case "${1:-}" in
  -h|--help)
    show_help
    exit 0
    ;;
  -V|--version)
    if go_bin="$(resolve_millennium_go)"; then
      exec "$go_bin" -V
    fi
    if [[ -f "${SCRIPT_DIR}/../VERSION" ]]; then
      echo "millennium-upgrade $(tr -d '[:space:]' < "${SCRIPT_DIR}/../VERSION")"
      exit 0
    fi
    echo "Error: millennium not found (and no VERSION file)." >&2
    exit 1
    ;;
esac

if ! go_bin="$(resolve_millennium_go)"; then
  echo "Error: upgrade requires the Go millennium dispatcher (not found)." >&2
  echo "Install millennium-helpers or run 'make build' from a checkout." >&2
  exit 1
fi

MILLENNIUM_LEGACY=0 exec "$go_bin" upgrade "$@"
