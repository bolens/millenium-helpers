#!/usr/bin/env bash
# Configure systemd/Task Scheduler for Millennium auto-updates — thin-wrap to Go.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  cat << EOF
Usage: $(basename "$0") <COMMAND> [OPTIONS]

Commands:
  enable [CHANNEL]   Enable scheduled Millennium updates
  disable            Disable scheduled updates
  status             Show scheduler status
  setup              Interactive configuration wizard
  config …           Get/set/list helper config
  pre-update         Scheduler pre-update hook
  post-update        Scheduler post-update hook

Options:
  -c, --channel CHANNEL   Update channel (stable/beta/main)
  --cron                  Prefer cron (Linux)
  --system|--user         systemd scope (Linux)
  -d, --dry-run  -q, --quiet  -V, --version  -h, --help
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
  -h|--help|"")
    show_help
    [[ -n "${1:-}" ]] || exit 1
    exit 0
    ;;
  -V|--version)
    if go_bin="$(resolve_millennium_go)"; then
      exec "$go_bin" schedule -V
    fi
    if [[ -f "${SCRIPT_DIR}/../VERSION" ]]; then
      echo "millennium-schedule $(tr -d '[:space:]' < "${SCRIPT_DIR}/../VERSION")"
      exit 0
    fi
    echo "Error: millennium not found (and no VERSION file)." >&2
    exit 1
    ;;
esac

if ! go_bin="$(resolve_millennium_go)"; then
  echo "Error: schedule requires the Go millennium dispatcher (not found)." >&2
  echo "Install millennium-helpers or run 'make build' from a checkout." >&2
  exit 1
fi

MILLENNIUM_LEGACY=0 exec "$go_bin" schedule "$@"
