#!/usr/bin/env bash
# Fix Millennium settings panel and ownership — thin-wrap to Go.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Fix Millennium settings panel, ownership, hooks, and related Steam files.

Options:
  -s, --skip-theme  Skip theme asset refresh
  -d, --dry-run     Simulate operations without modifying files
  -q, --quiet       Suppress informational output
  -y, --yes         Skip confirmation when closing Steam
  -V, --version     Show version information
  -h, --help        Show this help message
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
      echo "millennium-repair $(tr -d '[:space:]' < "${SCRIPT_DIR}/../VERSION")"
      exit 0
    fi
    echo "Error: millennium not found (and no VERSION file)." >&2
    exit 1
    ;;
esac

if ! go_bin="$(resolve_millennium_go)"; then
  echo "Error: repair requires the Go millennium dispatcher (not found)." >&2
  echo "Install millennium-helpers or run 'make build' from a checkout." >&2
  exit 1
fi

MILLENNIUM_LEGACY=0 exec "$go_bin" repair "$@"
