# shellcheck shell=bash
# Schedule helpers for millennium-schedule.sh (schedule_timer.sh)

# Overridable for tests (matches Go MILLENNIUM_SYSTEMD_SYSTEM_DIR).
system_systemd_dir() {
  echo "${MILLENNIUM_SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"
}

can_use_system_systemd() {
  local dir
  dir="$(system_systemd_dir)"
  if [[ -z "${MILLENNIUM_SYSTEMD_SYSTEM_DIR:-}" && ! -d /run/systemd/system ]]; then
    return 1
  fi
  mkdir -p "$dir" 2>/dev/null || true
  [[ -w "$dir" ]]
}

# Remove system-scope millennium-update units when permitted.
remove_system_systemd_units() {
  local dir timer_file service_file
  dir="$(system_systemd_dir)"
  timer_file="${dir}/${TIMER_NAME}"
  service_file="${dir}/${SERVICE_NAME}"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would stop/disable/remove system units under ${dir}${NC}"
    return 0
  fi

  if ! can_use_system_systemd; then
    if [[ -f "$timer_file" || -f "$service_file" ]]; then
      echo -e "${YELLOW}Warning: system units present but not removable without privileges; skipping system scope.${NC}" >&2
    fi
    return 1
  fi

  systemctl disable --now "$TIMER_NAME" 2>/dev/null || true
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$timer_file" "$service_file"
  systemctl daemon-reload 2>/dev/null || true
  return 0
}

enable_timer() {
  local channel
  channel="$(require_update_channel "${1:-${CONFIG_UPDATE_CHANNEL:-stable}}")" || exit 1
  local script_file=""

  script_file=$(resolve_packaged_helper_path "millennium-upgrade")

  # Sanity check: Ensure scripts have been installed (only if not dry run)
  if [[ "$DRY_RUN" == "false" ]] && [[ ! -f "$script_file" ]]; then
    echo -e "${RED}Error: Installed updater script not found at ${script_file}.${NC}" >&2
    if [[ "$(uname)" == "Darwin" ]]; then
      echo -e "${YELLOW}Please install the helper tools first via Homebrew.${NC}" >&2
    else
      echo -e "${YELLOW}Please run the installer first: sudo ./install.sh${NC}" >&2
    fi
    exit 1
  fi

  local theme_cmd
  theme_cmd=$(resolve_packaged_helper_path "millennium-theme")

  local sched_self
  sched_self=$(resolve_packaged_helper_path "millennium-schedule")

  local state_dir="${XDG_STATE_HOME:-$USER_HOME/.local/state}/millennium-helpers"

  if [[ "$(uname)" == "Darwin" ]]; then
    local plist_dir="${USER_HOME}/Library/LaunchAgents"
    local plist_path="${plist_dir}/com.millennium.update.plist"

    execute mkdir -p "$plist_dir"

    echo -e "${BLUE}Creating launchd plist file...${NC}"
    # Channel is allow-listed (stable|beta|main); paths come from packaged resolve.
    write_file "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.millennium.update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>mkdir -p '${state_dir}' && { MILLENNIUM_SCHEDULER=1 '${sched_self}' pre-update && '${script_file}' --channel '${channel}' && '${theme_cmd}' update && MILLENNIUM_SCHEDULER=1 '${sched_self}' post-update; } >> '${state_dir}/updater.log' 2>&1</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/com.millennium.update.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/com.millennium.update.stderr.log</string>
</dict>
</plist>
EOF

    echo -e "${BLUE}Loading launchd agent...${NC}"
    if [[ "$DRY_RUN" == "false" ]]; then
      launchctl unload "$plist_path" 2>/dev/null || true
      launchctl load "$plist_path"
    else
      echo -e "${YELLOW}[DRY RUN] Would load launchd agent: ${plist_path}${NC}"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
      echo -e "${GREEN}Dry run: LaunchAgent enablement simulated successfully.${NC}"
    else
      echo -e "${GREEN}Millennium auto-update LaunchAgent (${channel}) has been enabled!${NC}"
      echo -e "It will run daily at 2:00 AM."
    fi
    echo -e "\nYou can check the status with: millennium schedule status"
    return 0
  fi

  # Legacy Bash enable writes user units; clear system scope when possible so
  # doctor refresh / enable cannot leave dual timers active.
  if can_use_system_systemd || [[ -f "$(system_systemd_dir)/${TIMER_NAME}" || -f "$(system_systemd_dir)/${SERVICE_NAME}" ]]; then
    echo -e "${BLUE}Clearing conflicting systemd system-scope units (if any)...${NC}"
    remove_system_systemd_units || true
  fi

  # Ensure user systemd config directory exists
  execute mkdir -p "$USER_CONFIG_DIR"

  echo -e "${BLUE}Creating systemd user service file...${NC}"
  write_file "$SERVICE_PATH" << EOF
[Unit]
Description=Auto-update Millennium client (${channel}) and themes
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'mkdir -p "${state_dir}" && { MILLENNIUM_SCHEDULER=1 "${sched_self}" pre-update && /usr/bin/sudo -n "${script_file}" --channel "${channel}" --quiet && "${theme_cmd}" update --quiet && MILLENNIUM_SCHEDULER=1 "${sched_self}" post-update; } >> "${state_dir}/updater.log" 2>&1'
EOF

  echo -e "${BLUE}Creating systemd user timer file...${NC}"
  write_file "$TIMER_PATH" << EOF
[Unit]
Description=Trigger Millennium auto-update daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF

  if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" && "$DRY_RUN" == "false" ]]; then
    execute chown -R "${RUNNING_USER}:${RUNNING_USER}" "$USER_CONFIG_DIR"
  fi

  echo -e "${BLUE}Reloading systemd user daemon...${NC}"
  execute sysctl_user daemon-reload

  echo -e "${BLUE}Enabling and starting ${TIMER_NAME}...${NC}"
  execute sysctl_user enable --now "$TIMER_NAME"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}Dry run: Timer enablement simulated successfully.${NC}"
  else
    echo -e "${GREEN}Millennium auto-update user timer (${channel}) has been enabled!${NC}"
    echo -e "It will run daily with a randomized delay of up to 1 hour."
  fi

  # Verify passwordless sudo for the real user (not root when invoked via sudo)
  local sudo_list_cmd=(sudo -n -l)
  if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
    sudo_list_cmd=(sudo -U "$RUNNING_USER" -n -l)
  fi
  if ! "${sudo_list_cmd[@]}" 2>/dev/null | grep -qE "NOPASSWD.*(millennium-upgrade|ALL)"; then
    echo -e "\n${YELLOW}Warning: Passwordless sudo for the updater script could not be verified.${NC}"
    echo -e "Make sure you have run the installer first: sudo ./install.sh"
    echo -e "This configuration is required for the background timer to run successfully."
  else
    echo -e "\n${GREEN}Sudo Passwordless Configuration:${NC}"
    echo -e "The installer has automatically configured the required passwordless sudo rule at:"
    echo -e "  /etc/sudoers.d/millennium-helpers"
  fi

  # Print systemd user lingering tip
  echo -e "\n${GREEN}Systemd User Lingering (Optional):${NC}"
  echo -e "To allow user timers to run in the background even when you are logged out, enable user lingering:"
  echo -e "  loginctl enable-linger ${RUNNING_USER}"

  echo -e "\nYou can check the status of the timer with: millennium schedule status"
}

disable_timer() {
  if [[ "$(uname)" == "Darwin" ]]; then
    local plist_path="${USER_HOME}/Library/LaunchAgents/com.millennium.update.plist"
    echo -e "${BLUE}Disabling and unloading Millennium update LaunchAgent...${NC}"
    if [[ "$DRY_RUN" == "false" ]]; then
      launchctl unload "$plist_path" 2>/dev/null || true
      if [[ -f "$plist_path" ]]; then
        rm -f "$plist_path"
      fi
    else
      echo -e "${YELLOW}[DRY RUN] Would unload and remove LaunchAgent: ${plist_path}${NC}"
    fi
    echo -e "${GREEN}Millennium auto-update LaunchAgent has been disabled and removed.${NC}"
    return 0
  fi

  local sys_dir
  sys_dir="$(system_systemd_dir)"
  echo -e "${BLUE}Disabling Millennium update systemd timers (system and user scopes)...${NC}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would stop/disable/remove system units under ${sys_dir}${NC}"
    echo -e "${YELLOW}[DRY RUN] Would stop/disable/remove user units under ${USER_CONFIG_DIR}${NC}"
    echo -e "${GREEN}Dry run: Timer disablement simulated successfully.${NC}"
    return 0
  fi

  local had=false
  local sys_timer="${sys_dir}/${TIMER_NAME}"
  local sys_service="${sys_dir}/${SERVICE_NAME}"
  if can_use_system_systemd || [[ -f "$sys_timer" || -f "$sys_service" ]]; then
    if remove_system_systemd_units; then
      had=true
    fi
  fi

  if sysctl_user is-active --quiet "$TIMER_NAME" || sysctl_user is-enabled --quiet "$TIMER_NAME" 2>/dev/null; then
    sysctl_user disable --now "$TIMER_NAME" || true
    had=true
  fi

  if sysctl_user is-active --quiet "$SERVICE_NAME"; then
    sysctl_user stop "$SERVICE_NAME" || true
    had=true
  fi

  if [[ -f "$TIMER_PATH" ]]; then
    echo "Removing timer file: $TIMER_PATH"
    rm -f "$TIMER_PATH"
    had=true
  fi

  if [[ -f "$SERVICE_PATH" ]]; then
    echo "Removing service file: $SERVICE_PATH"
    rm -f "$SERVICE_PATH"
    had=true
  fi

  echo -e "${BLUE}Reloading systemd user daemon...${NC}"
  sysctl_user daemon-reload || true

  if [[ "$had" == "true" ]]; then
    echo -e "${GREEN}Millennium auto-update systemd timers have been disabled and removed (where permitted).${NC}"
  else
    echo -e "${GREEN}No systemd timer units found to disable.${NC}"
  fi
}
