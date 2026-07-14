# shellcheck shell=bash
# Schedule helpers for millennium-schedule.sh (schedule_status.sh)

show_status() {
  local scheduler_configured=false

  if [[ "$(uname)" == "Darwin" ]]; then
    local plist_path="${USER_HOME}/Library/LaunchAgents/com.millennium.update.plist"
    echo -e "${BLUE}=== Millennium LaunchAgent Status ===${NC}"
    if [[ -f "$plist_path" ]]; then
      scheduler_configured=true
      echo "LaunchAgent plist file exists: $plist_path"
      launchctl list | grep "com.millennium.update" || echo "LaunchAgent is registered but currently idle."
    else
      echo -e "${YELLOW}LaunchAgent is not installed/configured.${NC}"
    fi

    if command -v crontab &>/dev/null; then
      echo -e "\n${BLUE}=== Millennium Crontab Status ===${NC}"
      if crontab_for_user -l 2>/dev/null | grep -q "millennium-schedule"; then
        scheduler_configured=true
        crontab_for_user -l 2>/dev/null | grep "millennium-schedule"
      else
        echo "No crontab entry configured."
      fi
    fi
    if [[ "$scheduler_configured" != "true" ]]; then
      echo -e "\n${YELLOW}Scheduler disabled.${NC} Enable with: ${GREEN}millennium schedule enable [stable|beta|main]${NC}"
    else
      local state_dir="${XDG_STATE_HOME:-$USER_HOME/.local/state}/millennium-helpers"
      local log_file="${state_dir}/updater.log"
      local channel_disp="${CONFIG_UPDATE_CHANNEL:-${CHANNEL:-stable}}"
      echo -e "\n${BLUE}=== Scheduler summary ===${NC}"
      echo -e "  Channel     : ${channel_disp}"
      if [[ -f "$log_file" ]]; then
        echo -e "  Last log    : ${log_file}"
        echo -e "  View logs   : ${GREEN}millennium diag logs${NC}"
      else
        echo -e "  Last log    : (none yet — runs after the first scheduled update)"
      fi
      echo -e "  Disable     : ${GREEN}millennium schedule disable${NC}"
    fi
    return 0
  fi

  echo -e "${BLUE}=== Millennium User Update Timer Status ===${NC}"
  if [[ -f "$TIMER_PATH" ]]; then
    scheduler_configured=true
    sysctl_user status "$TIMER_NAME" || true
  else
    echo -e "${YELLOW}Timer is not installed/configured.${NC}"
  fi

  echo -e "\n${BLUE}=== Millennium User Update Service Status ===${NC}"
  if [[ -f "$SERVICE_PATH" ]]; then
    scheduler_configured=true
    sysctl_user status "$SERVICE_NAME" || true
  else
    echo -e "${YELLOW}Service is not installed/configured.${NC}"
  fi

  if command -v crontab &>/dev/null; then
    echo -e "\n${BLUE}=== Millennium Crontab Status ===${NC}"
    if crontab_for_user -l 2>/dev/null | grep -q "millennium-schedule"; then
      scheduler_configured=true
      crontab_for_user -l 2>/dev/null | grep "millennium-schedule"
    else
      echo "No crontab entry configured."
    fi
  fi

  if [[ "$scheduler_configured" != "true" ]]; then
    echo -e "\n${YELLOW}Scheduler disabled.${NC} Enable with: ${GREEN}millennium schedule enable [stable|beta|main]${NC}"
  else
    local state_dir="${XDG_STATE_HOME:-$USER_HOME/.local/state}/millennium-helpers"
    local log_file="${state_dir}/updater.log"
    local channel_disp="${CONFIG_UPDATE_CHANNEL:-${CHANNEL:-stable}}"
    # Prefer channel from installed service unit when present
    if [[ -f "$SERVICE_PATH" ]] && grep -q -- '--channel' "$SERVICE_PATH" 2>/dev/null; then
      channel_disp=$(grep -oE -- '--channel[[:space:]]+[a-z]+' "$SERVICE_PATH" | awk '{print $2; exit}' || echo "$channel_disp")
    fi
    echo -e "\n${BLUE}=== Scheduler summary ===${NC}"
    echo -e "  Channel     : ${channel_disp}"
    if [[ -f "$log_file" ]]; then
      echo -e "  Last log    : ${log_file}"
      echo -e "  View logs   : ${GREEN}millennium diag logs${NC}"
    else
      echo -e "  Last log    : (none yet — runs after the first scheduled update)"
    fi
    echo -e "  Disable     : ${GREEN}millennium schedule disable${NC}"
  fi
}

rotate_logs() {
  local state_dir="${XDG_STATE_HOME:-$USER_HOME/.local/state}/millennium-helpers"
  local log_file="${state_dir}/updater.log"
  [[ -f "$log_file" ]] || return 0

  local max_size=$((5 * 1024 * 1024)) # 5MB
  local file_size
  file_size=$(get_file_size "$log_file")

  if [[ "$file_size" -gt "$max_size" ]]; then
    # Rotate older logs
    [[ -f "${log_file}.2" ]] && mv -f "${log_file}.2" "${log_file}.3"
    [[ -f "${log_file}.1" ]] && mv -f "${log_file}.1" "${log_file}.2"
    # Copy current log to .1 and truncate current log
    cp -p "$log_file" "${log_file}.1"
    : > "$log_file"
    echo "Log file rotated (exceeded 5MB limit)." > "$log_file"
  fi
}
