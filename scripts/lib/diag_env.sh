# shellcheck shell=bash
# shellcheck disable=SC2034 # status globals read by millennium-diag.sh / doctor
# Config permissions, sudoers, and scheduler checks
check_directory_permissions() {
  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    PERMISSIONS_OK=true
    SKINS_DIR_OK=true
    return
  fi
  echo -e "\nMillennium Config & Theme Directory Permissions:"
  # A. Millennium User Config Directory
  local millennium_user_config=""
  if [[ -n "$user_xdg" ]]; then
    millennium_user_config="${user_xdg}/millennium"
  else
    millennium_user_config="${USER_HOME}/.config/millennium"
  fi

  if [[ -d "$millennium_user_config" ]]; then
    local config_owner
    config_owner=$(get_file_owner "$millennium_user_config")
    [[ -z "$config_owner" ]] && config_owner="unknown"
    if [[ ! -w "$millennium_user_config" ]]; then
      PERMISSIONS_OK=false
      unwritable_dirs+=("$millennium_user_config")
      print_diag_item "error" "  - Config Directory (${millennium_user_config})" "Not Writable (Owned by: ${config_owner})"
    else
      print_diag_item "ok" "  - Config Directory (${millennium_user_config})" "Writable (Owned by: ${config_owner})"
    fi
  else
    print_diag_item "ok" "  - Config Directory (${millennium_user_config})" "Not Created Yet (will be created automatically by Millennium)"
  fi

  # B. Steam Skins/Themes directories
  for steam_dir in "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root" "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam" "${USER_HOME}/Library/Application Support/Steam"; do
    [[ -d "$steam_dir" ]] || continue
    local skins_dir="${steam_dir}/steamui/skins"
    local type_env="Native"
    if [[ "$steam_dir" == *"com.valvesoftware.Steam"* ]]; then
      type_env="Flatpak"
    fi

    if [[ -d "$skins_dir" ]]; then
      local skins_owner
      skins_owner=$(get_file_owner "$skins_dir")
      [[ -z "$skins_owner" ]] && skins_owner="unknown"
      if [[ ! -w "$skins_dir" ]]; then
        PERMISSIONS_OK=false
        unwritable_dirs+=("$skins_dir")
        print_diag_item "error" "  - Skins Directory [${type_env}] (${skins_dir})" "Not Writable (Owned by: ${skins_owner})"
      else
        print_diag_item "ok" "  - Skins Directory [${type_env}] (${skins_dir})" "Writable (Owned by: ${skins_owner})"
      fi
    else
      # Skins directory doesn't exist, check parent
      local parent_dir
      parent_dir=$(dirname "$skins_dir")
      if [[ -d "$parent_dir" ]]; then
        local parent_owner
        parent_owner=$(get_file_owner "$parent_dir")
        [[ -z "$parent_owner" ]] && parent_owner="unknown"
        if [[ ! -w "$parent_dir" ]]; then
          PERMISSIONS_OK=false
          unwritable_dirs+=("$parent_dir")
          print_diag_item "error" "  - Skins Parent [${type_env}] (${parent_dir})" "Parent Not Writable (Owned by: ${parent_owner})"
        else
          print_diag_item "warn" "  - Skins Directory [${type_env}] (${skins_dir})" "Missing (parent is writable, will be created automatically)"
          SKINS_DIR_OK=false
          missing_skins_dirs+=("$skins_dir")
        fi
      else
        print_diag_item "error" "  - Skins Directory [${type_env}] (${skins_dir})" "Steam Directory Missing"
      fi
    fi
  done
  echo ""
}

check_sudoers_authorization() {
  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    SUDOERS_OK=true
    return
  fi
  local check_cmd="sudo -n -l"
  if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
    check_cmd="sudo -U $RUNNING_USER -n -l"
  fi

  if eval "$check_cmd" 2>/dev/null | grep -qE "NOPASSWD.*(millennium-upgrade|ALL)"; then
    print_diag_item "ok" "Sudoers Passwordless Update Authorization" "Active & Verified"
  else
    SUDOERS_OK=false
    print_diag_item "error" "Sudoers Passwordless Update Authorization" "Not Configured / Unauthorized"
  fi
}

check_scheduler_status() {
  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    TIMER_ACTIVE=true
    LINGER_OK=true
    return
  fi
  if [[ "$SYSTEMD_BOOTED" == "true" ]]; then
    local timer_path="${USER_CONFIG_DIR}/millennium-update.timer"
    if [[ -f "$timer_path" ]] && sysctl_user is-enabled millennium-update.timer &>/dev/null; then
      local timer_state
      timer_state=$(sysctl_user is-active millennium-update.timer || echo "inactive")
      if [[ "$timer_state" == "active" ]]; then
        local timer_trigger
        timer_trigger=$(sysctl_user list-timers millennium-update.timer --no-legend | awk '{print $1, $2, $3}')
        print_diag_item "ok" "Systemd Auto-Update Timer" "Enabled and Active (Next Run: ${timer_trigger})"
      else
        TIMER_ACTIVE=false
        print_diag_item "warn" "Systemd Auto-Update Timer" "Enabled but Inactive (timer is sleeping)"
      fi
    else
      TIMER_ACTIVE=false
      print_diag_item "error" "Systemd Auto-Update Timer" "Disabled / Not Scheduled"
    fi

    # Check Systemd User Lingering status
    if [[ -f "/var/lib/systemd/linger/${RUNNING_USER}" ]]; then
      print_diag_item "ok" "Systemd User Lingering" "Enabled"
    else
      LINGER_OK=false
      print_diag_item "warn" "Systemd User Lingering" "Disabled (Updates will only trigger when user is logged in)"
    fi
  else
    if command -v crontab &>/dev/null; then
      if crontab -l 2>/dev/null | grep -q "millennium-schedule"; then
        print_diag_item "ok" "Cron Auto-Update Scheduler" "Enabled and Active (Crontab entry configured)"
      else
        TIMER_ACTIVE=false
        print_diag_item "error" "Cron Auto-Update Scheduler" "Disabled / Not Scheduled"
      fi
    else
      TIMER_ACTIVE=false
      print_diag_item "error" "Cron Auto-Update Scheduler" "Disabled (No 'crontab' utility found)"
    fi
  fi
}
