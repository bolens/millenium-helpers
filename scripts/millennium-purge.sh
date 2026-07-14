#!/usr/bin/env bash
# De-register and purge Millennium client from Steam — thin-wrap to Go (Phase 6r).
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

DRY_RUN=false
QUIET=false
ASSUME_YES=false

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

De-register and purge Millennium client hooks and files from Steam.

Options:
  -d, --dry-run  Simulate operations without modifying files
  -q, --quiet    Suppress informational output
  -y, --yes      Skip the interactive confirmation prompt
  -V, --version  Show version information
  -h, --help     Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -q|--quiet)
      export QUIET=true
      export MILLENNIUM_QUIET=1
      shift
      ;;
    -y|--yes)
      ASSUME_YES=true
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
      echo "Unknown option: $1" >&2
      echo "Try '$(basename "$0") --help' for usage." >&2
      exit 1
      ;;
  esac
done

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

run_purge_via_go() {
  local go_bin
  if ! go_bin="$(resolve_millennium_go)"; then
    echo -e "${RED}Error: purge requires the Go millennium dispatcher (not found).${NC}" >&2
    echo "Install millennium-helpers or run 'make build' from a checkout." >&2
    exit 1
  fi
  local -a go_args=(purge)
  if [[ "$DRY_RUN" == "true" ]]; then
    go_args+=(--dry-run)
  fi
  if [[ "${QUIET:-false}" == "true" ]]; then
    go_args+=(--quiet)
  fi
  if [[ "$ASSUME_YES" == "true" ]]; then
    go_args+=(--yes)
  fi
  MILLENNIUM_LEGACY=0 exec "$go_bin" "${go_args[@]}"
}

run_purge_via_go
