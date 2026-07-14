#!/usr/bin/env bash
# Millennium Theme CLI Manager — thin-wrap to Go.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  cat << EOF
Usage: $(basename "$0") [COMMAND] [ARGUMENTS] [OPTIONS]

Commands:
  list                  List all installed Millennium themes
  install [owner/repo]  Install a theme from a GitHub repository
  update [theme-name]   Update an installed theme to its latest commit
  remove [theme-name]   Uninstall/remove an installed theme

Options:
  --json                Output list command results in structured JSON format
  -d, --dry-run         Perform a dry-run (simulates operations without modifying files)
  -q, --quiet           Suppress informational output
  -y, --yes             Skip confirmation when removing a theme
  -V, --version         Show version information
  -h, --help            Show this help message

Examples:
  millennium theme install SteamClientHomebrew/millennium-steam-skin
  millennium-theme update --all
  millennium-theme remove millennium-steam-skin
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
      echo "millennium-theme $(tr -d '[:space:]' < "${SCRIPT_DIR}/../VERSION")"
      exit 0
    fi
    echo "Error: millennium not found (and no VERSION file)." >&2
    exit 1
    ;;
esac

if ! go_bin="$(resolve_millennium_go)"; then
  echo "Error: theme requires the Go millennium dispatcher (not found)." >&2
  echo "Install millennium-helpers or run 'make build' from a checkout." >&2
  exit 1
fi

MILLENNIUM_LEGACY=0 exec "$go_bin" theme "$@"
