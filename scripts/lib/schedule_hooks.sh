# shellcheck shell=bash
# Schedule helpers for millennium-schedule.sh (schedule_hooks.sh)

# Moved from schedule_status.sh (Phase 6i peel) — pre-update still needs this.
rotate_logs() {
  local state_dir="${XDG_STATE_HOME:-$USER_HOME/.local/state}/millennium-helpers"
  local log_file="${state_dir}/updater.log"
  [[ -f "$log_file" ]] || return 0

  local max_size=$((5 * 1024 * 1024)) # 5MB
  local file_size
  file_size=$(get_file_size "$log_file")

  if [[ "$file_size" -gt "$max_size" ]]; then
    [[ -f "${log_file}.2" ]] && mv -f "${log_file}.2" "${log_file}.3"
    [[ -f "${log_file}.1" ]] && mv -f "${log_file}.1" "${log_file}.2"
    cp -p "$log_file" "${log_file}.1"
    : > "$log_file"
    echo "Log file rotated (exceeded 5MB limit)." > "$log_file"
  fi
}

pre_update() {
  if [[ "${MILLENNIUM_SCHEDULER:-}" != "1" ]]; then
    echo -e "${RED}Error: pre-update is only for the scheduler. Do not invoke it manually.${NC}" >&2
    echo "Enable or run updates via: millennium-schedule enable | millennium-upgrade" >&2
    exit 1
  fi
  rotate_logs
  log_info "Initiating pre-update checks..."
  if is_game_running; then
    log_warn "A game is currently running under Steam. Aborting update run."
    exit 75
  fi

  if pgrep -x steam >/dev/null; then
    log_info "Steam is running. Closing Steam gracefully to perform upgrades..."
    # Capture env
    capture_steam_env "$RUNNING_USER"

    # Close Steam
    close_steam_gracefully "$RUNNING_USER"
    log_info "Steam closed successfully."
  else
    log_info "Steam is not running. No close required."
  fi
  exit 0
}

post_update() {
  if [[ "${MILLENNIUM_SCHEDULER:-}" != "1" ]]; then
    echo -e "${RED}Error: post-update is only for the scheduler. Do not invoke it manually.${NC}" >&2
    echo "Enable or run updates via: millennium-schedule enable | millennium-upgrade" >&2
    exit 1
  fi
  log_info "Initiating post-update checks and verification..."
  local state_file
  state_file="$(relaunch_state_file "$RUNNING_USER")"
  local diag_path
  diag_path=$(resolve_helper_path "millennium-diag")

  if ! "$diag_path" >/dev/null 2>&1; then
    log_error "Millennium update failed verification checks. Relaunch cancelled."
    rm -f "$state_file"
    exit 1
  fi

  log_info "Diagnostics verification passed successfully."
  if _is_safe_relaunch_state_file "$RUNNING_USER" "$state_file"; then
    # Source saved environment variables (sets DISPLAY, WAYLAND_DISPLAY, STEAM_ARGS, WAS_FLATPAK, etc.)
    # shellcheck disable=SC1090
    source "$state_file"
    rm -f "$state_file"

    log_info "Relaunching Steam client with arguments: ${STEAM_ARGS:-none} (Flatpak: ${WAS_FLATPAK:-false})..."
    if [[ -n "${TEST_SUITE_RUN:-}" ]]; then
      log_info "[TEST] Bypassing real Steam relaunch in test suite."
      return 0
    fi
    if [[ "${WAS_FLATPAK:-false}" == "true" ]]; then
      # shellcheck disable=SC2086
      flatpak run com.valvesoftware.Steam ${STEAM_ARGS} >/dev/null 2>&1 &
    else
      if command -v steam &>/dev/null; then
        # shellcheck disable=SC2086
        steam ${STEAM_ARGS} >/dev/null 2>&1 &
      elif [[ -x "${USER_HOME}/.local/bin/steam" ]]; then
        # shellcheck disable=SC2086
        "${USER_HOME}/.local/bin/steam" ${STEAM_ARGS} >/dev/null 2>&1 &
      fi
    fi
  else
    log_info "No saved relaunch state found. Steam will not be restarted."
  fi
  exit 0
}
