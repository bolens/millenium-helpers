#!/usr/bin/env bash
# Millennium Theme CLI Manager — thin-wrap to Go (Phase 6g).
set -euo pipefail

# Source shared helpers
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

COMMAND=""
ARG=""
DRY_RUN=false
QUIET=false
ASSUME_YES=false
OUTPUT_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    list|install|update|remove)
      COMMAND="$1"
      shift
      if [[ "$COMMAND" != "list" && $# -gt 0 ]]; then
        # -a/--all are valid ARG values for 'update' even though they start
        # with '-'; anything else starting with '-' is treated as an option.
        if [[ "$1" != -* || "$1" == "-a" || "$1" == "--all" ]]; then
          ARG="$1"
          shift
        fi
      fi
      ;;
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -q|--quiet)
      export QUIET=true
      export MILLENNIUM_QUIET=1
      shift
      ;;
    -V|--version)
      print_helpers_version
      exit 0
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      if [[ "$1" != -* ]]; then
        echo "Unknown command: $1" >&2
        suggestion="$(suggest_closest "$1" list install update remove || true)"
        if [[ -n "$suggestion" ]]; then
          echo "Did you mean '${suggestion}'?" >&2
        fi
      else
        echo "Unknown option: $1" >&2
      fi
      echo "Try '$(basename "$0") --help' for usage." >&2
      exit 1
      ;;
  esac
done

if [[ -z "$COMMAND" ]]; then
  show_help
  exit 1
fi

if [[ "$COMMAND" != "list" && "$COMMAND" != "update" && -z "$ARG" ]]; then
  echo -e "${RED}Error: Argument required for command '${COMMAND}'.${NC}" >&2
  exit 1
fi

# Prefer checkout/install binary over PATH mocks used by the test suite.
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

run_theme_via_go() {
  local go_bin
  if ! go_bin="$(resolve_millennium_go)"; then
    echo -e "${RED}Error: theme requires the Go millennium dispatcher (not found).${NC}" >&2
    echo "Install millennium-helpers or run 'make build' from a checkout." >&2
    exit 1
  fi
  local -a go_args=(theme "$COMMAND")
  if [[ "$DRY_RUN" == "true" ]]; then
    go_args+=(--dry-run)
  fi
  if [[ "${QUIET:-false}" == "true" ]]; then
    go_args+=(--quiet)
  fi
  if [[ "$ASSUME_YES" == "true" ]]; then
    go_args+=(--yes)
  fi
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    go_args+=(--json)
  fi
  if [[ -n "$ARG" ]]; then
    go_args+=("$ARG")
  fi
  # Avoid re-entering this long-name helper if MILLENNIUM_LEGACY is set.
  MILLENNIUM_LEGACY=0 exec "$go_bin" "${go_args[@]}"
}

run_theme_via_go
