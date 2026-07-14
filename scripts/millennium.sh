#!/usr/bin/env bash
# Dispatcher for Millennium Helpers: millennium <command> [args...]
set -euo pipefail

show_help() {
  cat << EOF
Usage: $(basename "$0") <command> [args...]

Commands:
  diag       Run diagnostics (millennium-diag)
  doctor     Alias for: diag doctor
  upgrade    Upgrade / install Millennium (millennium-upgrade)
  schedule   Manage auto-update scheduler (millennium-schedule)
  theme      Manage skins/themes (millennium-theme)
  repair     Repair hooks and ownership (millennium-repair)
  purge      Uninstall Millennium (millennium-purge)
  mcp        Run / register the MCP server (millennium-mcp)
  help       Show this help

Examples:
  millennium diag
  millennium doctor
  millennium upgrade --channel beta
  millennium schedule status
  millennium theme list
EOF
}

# Feature modules (sourced by this entrypoint — no thin aggregator).
# Intentionally does not source common.sh so the dispatcher stays lightweight.
DISPATCHER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_disp_lib="${DISPATCHER_SCRIPT_DIR}/lib"
if [[ ! -f "${_disp_lib}/dispatcher.sh" ]]; then
  for _cand in \
    "$(cd "${DISPATCHER_SCRIPT_DIR}/.." && pwd)/lib/millennium-helpers/lib" \
    "/usr/local/lib/millennium-helpers/lib" \
    "/usr/lib/millennium-helpers/lib"
  do
    if [[ -f "${_cand}/dispatcher.sh" ]]; then
      _disp_lib="$_cand"
      break
    fi
  done
  unset _cand
fi
if [[ ! -f "${_disp_lib}/dispatcher.sh" ]]; then
  echo "Error: dispatcher library not found." >&2
  exit 1
fi
# shellcheck source=lib/dispatcher.sh
source "${_disp_lib}/dispatcher.sh"
unset _disp_lib

cmd="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

# Natural alias: millennium doctor → millennium-diag doctor
if [[ "$cmd" == "doctor" ]]; then
  set -- doctor "$@"
  cmd="diag"
fi

case "$cmd" in
  help|-h|--help)
    show_help
    exit 0
    ;;
  -V|--version)
    if command -v millennium-diag &>/dev/null; then
      exec millennium-diag --version
    fi
    echo "millennium (dispatcher)"
    exit 0
    ;;
  diag|upgrade|schedule|theme|repair|purge|mcp)
    exec_dispatcher_command "$cmd" "$@" || exit 1
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    suggestion="$(suggest_command "$cmd" || true)"
    if [[ -n "$suggestion" ]]; then
      echo "Did you mean '${suggestion}'?" >&2
    fi
    echo "Run '$(basename "$0") help' for usage." >&2
    exit 1
    ;;
esac
