# shellcheck shell=bash
# Diagnostic report helpers for millennium-diag.sh
# Sourced by millennium-diag.sh (not via common.sh)
#
# Status flags below are read by millennium-diag.sh (JSON output / doctor).
# shellcheck disable=SC2034

_diag_use_unicode() {
  # Explicit opt-out only. Default to unicode glyphs for normal terminals;
  # set NO_UNICODE=1 for ASCII OK/WARN/FAIL markers.
  [[ -z "${NO_UNICODE:-}" ]]
}

print_diag_item() {
  local status="$1"
  local label="$2"
  local value="$3"
  local ok_g warn_g err_g

  if _diag_use_unicode; then
    ok_g="✔"
    warn_g="!"
    err_g="✘"
  else
    ok_g="OK"
    warn_g="WARN"
    err_g="FAIL"
  fi

  if [[ "$status" == "ok" ]]; then
    printf "  [${GREEN}%s${NC}] %-45s : %b\n" "$ok_g" "$label" "$value"
  elif [[ "$status" == "warn" ]]; then
    printf "  [${YELLOW}%s${NC}] %-45s : %b\n" "$warn_g" "$label" "$value"
  else
    printf "  [${RED}%s${NC}] %-45s : %b\n" "$err_g" "$label" "$value"
  fi
}

# --- Diagnostics Functions ---

check_steam_status() {
  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    STEAM_RUNNING=false
    return
  fi
  if pgrep -x steam >/dev/null 2>&1; then
    STEAM_RUNNING=true
    print_diag_item "ok" "Steam Client" "Running (PID: $(pgrep -x steam | head -n 1))"
  else
    print_diag_item "warn" "Steam Client" "Not Running"
  fi
}

check_binaries_integrity() {
  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    BINARIES_OK=true
    return
  fi
  if [[ -f "/usr/lib/millennium/version.txt" ]]; then
    if [[ ! -f "/usr/lib/millennium/libmillennium_bootstrap_x86.so" || \
          ! -f "/usr/lib/millennium/libmillennium_bootstrap_hhx64.so" || \
          ! -f "/usr/lib/millennium/libmillennium_x86.so" || \
          ! -f "/usr/lib/millennium/libmillennium_hhx64.so" || \
          ! -f "/usr/lib/millennium/libmillennium_pvs64" ]]; then
      BINARIES_OK=false
      print_diag_item "error" "Millennium Binary Version" "Corrupted (core libraries or wrapper binaries are missing)"
    elif [[ ! -f "/usr/lib/millennium/checksums.txt" ]]; then
      BINARIES_OK=false
      print_diag_item "error" "Millennium Binary Version" "Corrupted (missing integrity manifest /usr/lib/millennium/checksums.txt)"
    elif ! (cd /usr/lib/millennium && sha256sum -c checksums.txt &>/dev/null); then
      BINARIES_OK=false
      print_diag_item "error" "Millennium Binary Version" "Corrupted (cryptographic checksum verification failed!)"
    else
      print_diag_item "ok" "Millennium Binary Version" "v$(cat /usr/lib/millennium/version.txt) (${UPDATE_CHANNEL} channel) - Verified Healthy"
    fi
  else
    BINARIES_OK=false
    print_diag_item "error" "Millennium Binary Version" "Not Installed (missing /usr/lib/millennium/version.txt)"
  fi
}

check_bootstrap_hooks() {
  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    HOOKS_OK=true
    FLATPAK_OK=true
    return
  fi
  if [[ "$(uname)" == "Darwin" ]]; then
    return 0
  fi
  echo -e "\nBootstrap Hooks (for user ${RUNNING_USER}):"
  local found_steam=false
  broken_hooks=()
  missing_hooks=()

  for steam_dir in "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root" "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam" "${USER_HOME}/Library/Application Support/Steam"; do
    [[ -d "$steam_dir" ]] || continue
    found_steam=true
    
    # Determine environment type
    local type_env="Native"
    if [[ "$steam_dir" == *"com.valvesoftware.Steam"* ]]; then
      type_env="Flatpak"
    fi
    
    echo -e "  Steam path [${type_env}]: ${steam_dir}"
    
    for arch in "ubuntu12_32:x86" "ubuntu12_64:hhx64"; do
      local folder="${arch%%:*}"
      local lib_name="${arch#*:}"
      local hook_file="${steam_dir}/${folder}/libXtst.so.6"
      
      if [[ -L "$hook_file" ]]; then
        local target
        target=$(readlink "$hook_file")
        if [[ "$target" == *"/usr/lib/millennium/libmillennium_bootstrap_${lib_name}.so"* ]]; then
          if [[ -f "$target" ]]; then
            print_diag_item "ok" "    - Hook (${folder})" "Active and Verified"
          else
            HOOKS_OK=false
            broken_hooks+=("${steam_dir}:${folder}:${lib_name}")
            print_diag_item "error" "    - Hook (${folder})" "Broken Symlink (target does not exist)"
          fi
        else
          print_diag_item "warn" "    - Hook (${folder})" "Active, but points to custom library: ${target}"
        fi
      elif [[ -f "$hook_file" ]]; then
        print_diag_item "warn" "    - Hook (${folder})" "Replaced by a real file (non-symlink)"
      else
        HOOKS_OK=false
        missing_hooks+=("${steam_dir}:${folder}:${lib_name}")
        print_diag_item "error" "    - Hook (${folder})" "Inactive (missing symlink)"
      fi
    done

    # Flatpak specific checks
    if [[ "$type_env" == "Flatpak" ]]; then
      local flatpak_user_override="${USER_HOME}/.local/share/flatpak/overrides/com.valvesoftware.Steam"
      local flatpak_sys_override="/var/lib/flatpak/overrides/com.valvesoftware.Steam"
      local has_override=false
      
      for override_file in "$flatpak_user_override" "$flatpak_sys_override"; do
        if [[ -f "$override_file" ]] && grep -q "/usr/lib/millennium" "$override_file" 2>/dev/null; then
          has_override=true
          break
        fi
      done
      
      if [[ "$has_override" == true ]]; then
        print_diag_item "ok" "    - Flatpak Sandbox Override" "Configured (/usr/lib/millennium is visible inside container)"
      else
        FLATPAK_OK=false
        print_diag_item "error" "    - Flatpak Sandbox Override" "Missing!"
      fi
    fi
  done

  if [[ "$found_steam" == false ]]; then
    echo -e "  ${RED}No Steam directories detected for the current user.${NC}"
  fi
}

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

check_helper_updates() {
  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    SCRIPTS_UP_TO_DATE=true
    return
  fi
  echo -e "\nHelper Scripts Update Status:"
  ONLINE=false
  if curl -sIk "https://github.com" &>/dev/null; then
    ONLINE=true
  fi

  if [[ "$ONLINE" == "true" ]]; then
    TMP_SCRIPTS=$(mktemp -d)
    if [[ -z "$TMP_SCRIPTS" || ! -d "$TMP_SCRIPTS" ]]; then
      echo -e "${RED}Error: Failed to create temporary directory for updates check.${NC}" >&2
      return 1
    fi
    trap 'rm -rf "${TMP_SCRIPTS:-}"' EXIT INT TERM
    
    local latest_sha="main"
    local api_data
    if api_data=$(curl -sL --retry 3 --retry-delay 2 "https://api.github.com/repos/bolens/millenium-helpers/commits/main" 2>/dev/null); then
      local parsed_sha=""
      # Prefer python/jq over echo|grep -m1: grep closes early and can make
      # bash emit "Broken pipe" on stderr, which pollutes --json 2>&1 captures.
      if command -v python3 &>/dev/null; then
        parsed_sha=$(printf '%s' "$api_data" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('sha', ''))
except Exception:
    pass
" 2>/dev/null || true)
      elif command -v jq &>/dev/null; then
        parsed_sha=$(printf '%s' "$api_data" | jq -r '.sha // empty' 2>/dev/null || true)
      else
        parsed_sha=$(grep -m 1 '"sha":' <<<"$api_data" | cut -d'"' -f4 || true)
      fi
      if [[ "$parsed_sha" =~ ^[0-9a-f]{40}$ ]]; then
        latest_sha="$parsed_sha"
      fi
    fi

    for item in "${UTILITIES[@]}"; do
      local cmd_name="${item%%:*}"
      local remote_rel="${item#*:}"
      local local_path=""
      if [[ -f "/usr/bin/${cmd_name}" ]]; then
        local_path="/usr/bin/${cmd_name}"
      elif [[ -f "/usr/local/bin/${cmd_name}" ]]; then
        local_path="/usr/local/bin/${cmd_name}"
      fi
      
      local remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${latest_sha}/${remote_rel}"
      local tmp_dest="${TMP_SCRIPTS}/${cmd_name}"
      
      if [[ -n "$local_path" ]]; then
        if curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" &>/dev/null; then
          local local_sha
          local_sha=$(sha256sum "$local_path" | awk '{print $1}')
          local remote_sha
          remote_sha=$(sha256sum "$tmp_dest" | awk '{print $1}')
          
          if [[ "$local_sha" != "$remote_sha" ]]; then
            SCRIPTS_UP_TO_DATE=false
            out_of_date_scripts+=("$cmd_name")
            print_diag_item "error" "  - ${cmd_name}" "Out of date"
          else
            print_diag_item "ok" "  - ${cmd_name}" "Up to date"
          fi
        else
          print_diag_item "warn" "  - ${cmd_name}" "Unable to check (HTTP download failed)"
        fi
      else
        print_diag_item "error" "  - ${cmd_name}" "Not Installed"
        SCRIPTS_UP_TO_DATE=false
        if curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" &>/dev/null; then
          out_of_date_scripts+=("$cmd_name")
        fi
      fi
    done
  else
    echo -e "  ${YELLOW}System is offline. Skipping update checks for helper scripts.${NC}"
  fi
}

check_shell_completions() {
  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    COMPLETIONS_OK=true
    return
  fi
  echo -e "\nShell Autocompletions Status:"

  # Define paths and their corresponding remote repository locations using parallel arrays for Bash 3.2 compatibility
  local completion_paths=(
    "/usr/share/bash-completion/completions/millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-helpers"
    "/usr/share/fish/vendor_completions.d/millennium-repair.fish"
    "/usr/share/fish/vendor_completions.d/millennium-upgrade.fish"
    "/usr/share/fish/vendor_completions.d/millennium-schedule.fish"
    "/usr/share/fish/vendor_completions.d/millennium-purge.fish"
    "/usr/share/fish/vendor_completions.d/millennium-diag.fish"
    "/usr/share/fish/vendor_completions.d/millennium-theme.fish"
    "/usr/share/fish/vendor_completions.d/millennium-mcp.fish"
  )
  local completion_repos=(
    "completions/bash/millennium-helpers"
    "completions/zsh/_millennium-helpers"
    "completions/fish/millennium-repair.fish"
    "completions/fish/millennium-upgrade.fish"
    "completions/fish/millennium-schedule.fish"
    "completions/fish/millennium-purge.fish"
    "completions/fish/millennium-diag.fish"
    "completions/fish/millennium-theme.fish"
    "completions/fish/millennium-mcp.fish"
  )

  local nu_dest=""
  for base_dir in "/usr/share" "/usr/local/share"; do
    if [[ -d "${base_dir}/nushell/completions" ]]; then
      nu_dest="${base_dir}/nushell/completions/millennium-helpers.nu"
      break
    fi
  done
  if [[ -z "$nu_dest" ]]; then
    nu_dest="/usr/share/nushell/completions/millennium-helpers.nu"
  fi
  completion_paths+=("$nu_dest")
  completion_repos+=("completions/nushell/millennium-helpers.nu")

  declare -a COMPLETION_SYMLINKS=(
    "/usr/share/bash-completion/completions/millennium-repair:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-upgrade:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-schedule:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-purge:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-diag:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-theme:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-mcp:millennium-helpers"
    
    "/usr/share/zsh/site-functions/_millennium-repair:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-upgrade:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-schedule:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-purge:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-diag:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-theme:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-mcp:_millennium-helpers"
  )

  missing_completions=()
  out_of_date_completions=()

  for i in "${!completion_paths[@]}"; do
    local local_path="${completion_paths[$i]}"
    local remote_rel="${completion_repos[$i]}"
    local local_dir
    local_dir=$(dirname "$local_path")
    [[ -d "$local_dir" ]] || continue
    
    if [[ ! -f "$local_path" ]]; then
      COMPLETIONS_OK=false
      missing_completions+=("$local_path")
      print_diag_item "error" "  - $(basename "$local_path")" "Missing"
    elif [[ "${ONLINE:-false}" == "true" ]]; then
      local remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${latest_sha:-main}/${remote_rel}"
      local tmp_dest
      tmp_dest="${TMP_SCRIPTS}/comp_$(basename "$local_path")"
      
      if curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" &>/dev/null; then
        local local_sha
        local_sha=$(sha256sum "$local_path" | awk '{print $1}')
        local remote_sha
        remote_sha=$(sha256sum "$tmp_dest" | awk '{print $1}')
        if [[ "$local_sha" != "$remote_sha" ]]; then
          COMPLETIONS_OK=false
          out_of_date_completions+=("$local_path")
          print_diag_item "error" "  - $(basename "$local_path")" "Out of date"
        else
          print_diag_item "ok" "  - $(basename "$local_path")" "Up to date"
        fi
      else
        print_diag_item "warn" "  - $(basename "$local_path")" "Unable to check (HTTP download failed)"
      fi
    else
      print_diag_item "ok" "  - $(basename "$local_path")" "Present (offline, cannot verify version)"
    fi
  done

  broken_symlinks=()
  for symlink_item in "${COMPLETION_SYMLINKS[@]}"; do
    local symlink_path="${symlink_item%%:*}"
    local symlink_target="${symlink_item#*:}"
    local symlink_dir
    symlink_dir=$(dirname "$symlink_path")
    [[ -d "$symlink_dir" ]] || continue
    
    if [[ ! -L "$symlink_path" ]]; then
      COMPLETIONS_OK=false
      broken_symlinks+=("$symlink_path:$symlink_target")
      print_diag_item "error" "  - $(basename "$symlink_path") symlink" "Missing/Broken"
    else
      local target_resolved
      target_resolved=$(readlink "$symlink_path" || true)
      if [[ "$target_resolved" != "$symlink_target" ]]; then
        COMPLETIONS_OK=false
        broken_symlinks+=("$symlink_path:$symlink_target")
        print_diag_item "error" "  - $(basename "$symlink_path") symlink" "Incorrect target (${target_resolved})"
      fi
    fi
  done
}

check_obsolete_files() {
  echo -e "\nObsolete / Deprecated Legacy Files:"
  local obsolete_list=()
  if [[ -n "${DIAG_TEST_OBSOLETE_LIST:-}" ]]; then
    IFS=',' read -r -a obsolete_list <<< "$DIAG_TEST_OBSOLETE_LIST"
  else
    obsolete_list=(
      "/usr/bin/millennium-upgrade-stable"
      "/usr/bin/millennium-upgrade-beta"
      "/usr/local/bin/millennium-upgrade-stable"
      "/usr/local/bin/millennium-upgrade-beta"
      "/usr/share/bash-completion/completions/millennium-upgrade-stable"
      "/usr/share/bash-completion/completions/millennium-upgrade-beta"
      "/usr/local/share/bash-completion/completions/millennium-upgrade-stable"
      "/usr/local/share/bash-completion/completions/millennium-upgrade-beta"
      "/usr/share/zsh/site-functions/_millennium-upgrade-stable"
      "/usr/share/zsh/site-functions/_millennium-upgrade-beta"
      "/usr/local/share/zsh/site-functions/_millennium-upgrade-stable"
      "/usr/local/share/zsh/site-functions/_millennium-upgrade-beta"
      "/usr/share/fish/vendor_completions.d/millennium-upgrade-stable.fish"
      "/usr/share/fish/vendor_completions.d/millennium-upgrade-beta.fish"
      "/usr/local/share/fish/vendor_completions.d/millennium-upgrade-stable.fish"
      "/usr/local/share/fish/vendor_completions.d/millennium-upgrade-beta.fish"
    )
  fi

  local found_any=false
  # Bash 3.2 (macOS): empty "${arr[@]}" is unbound under set -u
  # (e.g. DIAG_TEST_OBSOLETE_LIST="" leaves obsolete_list empty).
  for f in ${obsolete_list[@]+"${obsolete_list[@]}"}; do
    if [[ -f "$f" || -L "$f" ]]; then
      found_any=true
      obsolete_files_found+=("$f")
    fi
  done

  if [[ "$found_any" == "true" ]]; then
    CLEAN_OF_OBSOLETE=false
    print_diag_item "warn" "Legacy Wrapper Files" "Detected ${#obsolete_files_found[@]} deprecated files needing cleanup"
  else
    print_diag_item "ok" "Legacy Wrapper Files" "None detected (Clean)"
  fi
}

print_diag_next_steps() {
  # Skip when JSON mode or doctor already running (caller decides).
  local issues=0
  local suggestions=()

  [[ "${BINARIES_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium upgrade --force        # repair/reinstall Millennium binaries"); }
  [[ "${HOOKS_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium repair                # restore bootstrap hooks"); }
  [[ "${FLATPAK_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("flatpak override --user --filesystem=/usr/lib/millennium com.valvesoftware.Steam"); }
  [[ "${PERMISSIONS_OK:-true}" == "true" && "${SKINS_DIR_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium repair                # fix ownership / skins directory"); }
  [[ "${SUDOERS_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("sudo ./install.sh install        # restore passwordless sudoers drop-in"); }
  [[ "${TIMER_ACTIVE:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium schedule enable       # enable daily auto-updates"); }
  [[ "${LINGER_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("sudo loginctl enable-linger ${RUNNING_USER:-$USER}  # keep user timers after logout"); }
  [[ "${SCRIPTS_UP_TO_DATE:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium doctor                # update helper scripts"); }
  [[ "${COMPLETIONS_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium doctor                # restore shell completions"); }
  [[ "${CLEAN_OF_OBSOLETE:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium doctor                # remove legacy wrapper files"); }

  echo ""
  if [[ "$issues" -eq 0 ]]; then
    echo -e "${GREEN}No issues detected. Your Millennium installation looks healthy.${NC}"
    echo -e "Tip: run ${YELLOW}millennium schedule status${NC} to review auto-updates, or ${YELLOW}millennium theme list${NC} for skins."
    return 0
  fi

  echo -e "${YELLOW}${issues} issue(s) detected.${NC} Suggested next steps:"
  local s
  # Deduplicate while preserving order
  local seen="|"
  for s in "${suggestions[@]}"; do
    [[ "$seen" == *"|${s}|"* ]] && continue
    seen+="${s}|"
    echo -e "  • ${s}"
  done
  echo -e "\nOr run ${GREEN}millennium doctor${NC} (alias: sudo millennium-diag doctor) to attempt automatic repairs."
}

run_diagnostics() {
  echo -e "${BLUE}=== Millennium Diagnostics Report ===${NC}\n"
  
  check_steam_status
  check_binaries_integrity
  check_bootstrap_hooks
  check_directory_permissions
  check_sudoers_authorization
  check_scheduler_status
  check_helper_updates
  check_shell_completions
  check_obsolete_files
}

