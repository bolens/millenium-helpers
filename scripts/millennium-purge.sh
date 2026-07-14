#!/usr/bin/env bash
# De-register and purge Millennium client from Steam
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
      # shellcheck disable=SC2034 # consumed by purge_ops.sh
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

if [[ "$DRY_RUN" == "false" ]] && [[ "$(id -u)" -ne 0 ]]; then
  echo -e "${RED}Error: This script must be run with sudo to remove system-wide files.${NC}" >&2
  echo -e "Please run: sudo $0" >&2
  exit 1
fi

# Feature modules (sourced by this entrypoint — no thin aggregator)
_feat_lib="${_COMMON_LIB_DIR:-${SCRIPT_DIR}/lib}"
if [[ ! -f "${_feat_lib}/purge_ops.sh" ]]; then
  _feat_lib="${SCRIPT_DIR}/lib"
fi
# shellcheck source=lib/purge_ops.sh
source "${_feat_lib}/purge_ops.sh"
unset _feat_lib

run_purge
