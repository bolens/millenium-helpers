#!/usr/bin/env bash
# Configure systemd user timer for Millennium auto-updates
set -euo pipefail

RUNNING_USER="${SUDO_USER:-$(id -un)}"

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
  echo -e "Error: Shared helper library not found." >&2
  exit 1
fi

USER_HOME="$(get_user_home "$RUNNING_USER")"


# Vars below are consumed by sourced schedule_* / repair_ops feature modules.
# shellcheck disable=SC2034
SERVICE_NAME="millennium-update.service"
# shellcheck disable=SC2034
TIMER_NAME="millennium-update.timer"
# Under sudo, ignore root's XDG_CONFIG_HOME and always use the invoking user's tree.
if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  USER_CONFIG_DIR="${USER_HOME}/.config/systemd/user"
else
  USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$USER_HOME/.config}/systemd/user"
fi
# shellcheck disable=SC2034
SERVICE_PATH="${USER_CONFIG_DIR}/${SERVICE_NAME}"
# shellcheck disable=SC2034
TIMER_PATH="${USER_CONFIG_DIR}/${TIMER_NAME}"

show_help() {
  cat << EOF
Usage: $(basename "$0") COMMAND [OPTIONS]

Commands:
  enable [stable|beta|main]  Enable the daily update timer (defaults to stable)
  disable               Disable the update timer/cron and service
  status                Show status of the systemd user service and cron job
  setup                 Run the interactive configuration wizard
  config [get/set/list] Manage Millennium Helper configuration options

Options:
  -c, --cron            Force use of crontab instead of systemd
  -d, --dry-run         Perform dry-run without writing files or changing systemd state
  -q, --quiet           Suppress informational output
  -V, --version         Show version information
  -h, --help            Show this help message
EOF
}

# Parse options and commands
COMMAND=""
DRY_RUN=false
QUIET=false
USE_CRON=false
if [[ ! -d /run/systemd/system ]]; then
  USE_CRON=true
fi
CHANNEL=""
CONFIG_ACTION=""
CONFIG_KEY=""
CONFIG_VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    enable|disable|status|setup|pre-update|post-update)
      COMMAND="$1"
      shift
      ;;
    config)
      COMMAND="config"
      shift
      if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
        CONFIG_ACTION="$1"
        shift
      else
        CONFIG_ACTION="list"
      fi
      if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
        CONFIG_KEY="$1"
        shift
      fi
      if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
        CONFIG_VALUE="$1"
        shift
      fi
      ;;
    stable|beta|main)
      CHANNEL="$1"
      shift
      ;;
    -c|--cron)
      USE_CRON=true
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
        if [[ -n "$COMMAND" ]]; then
          # Positional after a subcommand is usually a channel (stable|beta|main).
          echo -e "${RED}Unknown channel: $1${NC}" >&2
          echo "Valid channels: stable, beta, main" >&2
        else
          echo -e "${RED}Unknown command: $1${NC}" >&2
          suggestion="$(suggest_closest "$1" enable disable status setup config pre-update post-update || true)"
          if [[ -n "$suggestion" ]]; then
            echo "Did you mean '${suggestion}'?" >&2
          fi
        fi
      else
        echo -e "${RED}Unknown option: $1${NC}" >&2
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

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}=== DRY RUN MODE: No changes will be made ===${NC}"
fi

# Feature modules (sourced by this entrypoint — no thin aggregator)
_sched_lib="${_COMMON_LIB_DIR:-${SCRIPT_DIR}/lib}"
if [[ ! -f "${_sched_lib}/schedule_timer.sh" ]]; then
  _sched_lib="${SCRIPT_DIR}/lib"
fi
# shellcheck source=lib/schedule_timer.sh
source "${_sched_lib}/schedule_timer.sh"
# shellcheck source=lib/schedule_cron.sh
source "${_sched_lib}/schedule_cron.sh"
# shellcheck source=lib/schedule_status.sh
source "${_sched_lib}/schedule_status.sh"
# shellcheck source=lib/schedule_hooks.sh
source "${_sched_lib}/schedule_hooks.sh"
# shellcheck source=lib/schedule_wizard.sh
source "${_sched_lib}/schedule_wizard.sh"
unset _sched_lib

# Phase 6c: config is Go-only (thin-wrap). Prefer checkout/install binary over PATH
# mocks used by the test suite.
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

run_schedule_config_via_go() {
  local go_bin
  if ! go_bin="$(resolve_millennium_go)"; then
    echo -e "${RED}Error: schedule config requires the Go millennium dispatcher (not found).${NC}" >&2
    echo "Install millennium-helpers or run 'make build' from a checkout." >&2
    exit 1
  fi
  local -a go_args=(schedule config)
  if [[ "$DRY_RUN" == "true" ]]; then
    go_args+=(--dry-run)
  fi
  if [[ "${QUIET:-false}" == "true" ]]; then
    go_args+=(--quiet)
  fi
  go_args+=("${CONFIG_ACTION:-list}")
  if [[ -n "${CONFIG_KEY:-}" ]]; then
    go_args+=("$CONFIG_KEY")
  fi
  if [[ -n "${CONFIG_VALUE:-}" ]]; then
    go_args+=("$CONFIG_VALUE")
  fi
  # Avoid re-entering this long-name helper if MILLENNIUM_LEGACY is set.
  MILLENNIUM_LEGACY=0 exec "$go_bin" "${go_args[@]}"
}

case "$COMMAND" in
  enable)
    if [[ "$USE_CRON" == "true" ]]; then
      enable_cron "$CHANNEL"
    else
      enable_timer "$CHANNEL"
    fi
    ;;
  disable)
    disable_timer
    disable_cron
    ;;
  status)
    show_status
    ;;
  setup)
    run_setup_wizard
    ;;
  pre-update)
    pre_update
    ;;
  post-update)
    post_update
    ;;
  config)
    run_schedule_config_via_go
    ;;
esac
