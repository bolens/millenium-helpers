# shellcheck shell=bash
# shellcheck disable=SC2034 # status globals read by millennium-diag.sh / doctor
# Steam client, Millennium binaries, and bootstrap hook checks
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

