#!/usr/bin/env bash
# Diagnostics for Millennium helpers — thin-wrap to Go (Phase 6z).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH=""
for _common_candidate in \
  "${SCRIPT_DIR}/common.sh" \
  "$(cd "${SCRIPT_DIR}/.." && pwd)/lib/millennium-helpers/common.sh" \
  "/usr/local/lib/millennium-helpers/common.sh" \
  "/usr/lib/millennium-helpers/common.sh"
do
  if [[ -f "$_common_candidate" ]]; then
    COMMON_SH="$_common_candidate"
    break
  fi
done
unset _common_candidate
if [[ -f "$COMMON_SH" ]]; then
  # shellcheck disable=SC1090
  source "$COMMON_SH"
else
  echo -e "${RED:-}Error: Shared helper library not found." >&2
  exit 1
fi

show_help() {
  cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  (None)        Run read-only diagnostics report (default)
  doctor        Detect and automatically repair partial or broken installations
  logs          Display recent Millennium and Steam WebHelper startup logs

Options:
  -f, --fix     Alias for the 'doctor' command
  --force       Force all doctor repairs even if system is healthy
  --json        Output diagnostics report in structured JSON format
  -l, --follow  Follow (tail -f) real-time log output
  -y, --yes     Skip confirmation when doctor closes Steam
  -d, --dry-run Perform a dry-run (simulates doctor repairs without modifying anything)
  -q, --quiet   Suppress informational output
  -s, --share   Upload diagnostic report to a pastebin and return a short link
  -V, --version Show version information
  -h, --help    Show this help message
EOF
}

# Local help/version for offline suites; everything else goes to Go.
case "${1:-}" in
  -h|--help)
    show_help
    exit 0
    ;;
  -V|--version)
    print_helpers_version
    exit 0
    ;;
esac

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

if ! go_bin="$(resolve_millennium_go)"; then
  echo -e "${RED}Error: diag requires the Go millennium dispatcher (not found).${NC}" >&2
  echo "Install millennium-helpers or run 'make build' from a checkout." >&2
  exit 1
fi

MILLENNIUM_LEGACY=0 exec "$go_bin" diag "$@"
