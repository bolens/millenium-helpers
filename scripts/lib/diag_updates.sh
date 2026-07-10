# shellcheck shell=bash
# shellcheck disable=SC2034 # status globals read by millennium-diag.sh / doctor
# Helper script update checks vs latest release
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

  if [[ "$ONLINE" != "true" ]]; then
    echo -e "  ${YELLOW}System is offline. Skipping update checks for helper scripts.${NC}"
    return
  fi

  fetch_latest_release_tag || true

  if [[ "$INSTALL_METHOD" != "pacman" && "$INSTALL_METHOD" != "manual" && "$INSTALL_METHOD" != "mixed" && "$INSTALL_METHOD" != "none" ]]; then
    detect_install_method
  fi

  if [[ "$INSTALL_METHOD" == "pacman" ]] || helpers_are_pacman_packaged; then
    local item cmd_name local_path
    for item in "${UTILITIES[@]}"; do
      cmd_name="${item%%:*}"
      local_path="$(_diag_helper_local_path "$cmd_name")"
      if [[ -n "$local_path" ]]; then
        print_diag_item "ok" "  - ${cmd_name}" "Installed (pacman package)"
      else
        SCRIPTS_UP_TO_DATE=false
        out_of_date_scripts+=("$cmd_name")
        print_diag_item "error" "  - ${cmd_name}" "Not Installed"
      fi
    done

    local installed_ver=""
    installed_ver="$(get_helpers_version)"
    if [[ -n "${LATEST_RELEASE_VERSION:-}" && "$installed_ver" != "unknown" ]]; then
      if [[ "$installed_ver" == "$LATEST_RELEASE_VERSION" ]]; then
        print_diag_item "ok" "  - Package version" "v${installed_ver} (matches latest release ${LATEST_RELEASE_TAG})"
      else
        SCRIPTS_UP_TO_DATE=false
        print_diag_item "error" "  - Package version" "Installed v${installed_ver}, latest release is v${LATEST_RELEASE_VERSION} (${LATEST_RELEASE_TAG})"
      fi
    elif [[ -n "${LATEST_RELEASE_TAG:-}" ]]; then
      print_diag_item "warn" "  - Package version" "Could not determine installed version (latest release: ${LATEST_RELEASE_TAG})"
    fi
    return
  fi

  if [[ "$INSTALL_METHOD" == "none" ]]; then
    SCRIPTS_UP_TO_DATE=false
    local item cmd_name
    for item in "${UTILITIES[@]}"; do
      cmd_name="${item%%:*}"
      out_of_date_scripts+=("$cmd_name")
      print_diag_item "error" "  - ${cmd_name}" "Not Installed"
    done
    return
  fi

  if [[ "$INSTALL_METHOD" == "mixed" ]]; then
    SCRIPTS_UP_TO_DATE=false
    local item cmd_name local_path
    for item in "${UTILITIES[@]}"; do
      cmd_name="${item%%:*}"
      local_path="$(_diag_helper_local_path "$cmd_name")"
      if [[ -z "$local_path" ]]; then
        out_of_date_scripts+=("$cmd_name")
        print_diag_item "error" "  - ${cmd_name}" "Not Installed"
      elif command -v pacman >/dev/null 2>&1 && pacman -Qo "$local_path" >/dev/null 2>&1; then
        print_diag_item "warn" "  - ${cmd_name}" "Pacman-owned (${local_path})"
      else
        print_diag_item "warn" "  - ${cmd_name}" "Manual install (${local_path})"
      fi
    done
    print_diag_item "error" "  - Install layout" "Resolve mixed pacman/manual installs before updating"
    return
  fi

  # Manual install: compare against latest release tarball (single fetch).
  TMP_SCRIPTS=$(mktemp -d)
  if [[ -z "$TMP_SCRIPTS" || ! -d "$TMP_SCRIPTS" ]]; then
    echo -e "${RED}Error: Failed to create temporary directory for updates check.${NC}" >&2
    return 1
  fi
  trap 'rm -rf "${TMP_SCRIPTS:-}"; _diag_cleanup_release_workdir' EXIT INT TERM

  if ! diag_fetch_release_tarball; then
    print_diag_item "warn" "Release tarball" "Unable to download or verify latest release (${LATEST_RELEASE_TAG:-unknown})"
    return
  fi

  local item cmd_name remote_rel local_path release_path local_sha release_sha tmp_dest
  for item in "${UTILITIES[@]}"; do
    cmd_name="${item%%:*}"
    remote_rel="${item#*:}"
    local_path="$(_diag_helper_local_path "$cmd_name")"
    release_path="$(_diag_release_source_path "$remote_rel")"

    if [[ -z "$release_path" ]]; then
      print_diag_item "warn" "  - ${cmd_name}" "Missing from release tarball (${remote_rel})"
      continue
    fi

    if [[ -n "$local_path" ]]; then
      local_sha="$(_diag_file_sha256 "$local_path")"
      release_sha="$(_diag_file_sha256 "$release_path")"
      if [[ -n "$local_sha" && -n "$release_sha" && "$local_sha" == "$release_sha" ]]; then
        print_diag_item "ok" "  - ${cmd_name}" "Up to date (${LATEST_RELEASE_TAG})"
      else
        SCRIPTS_UP_TO_DATE=false
        out_of_date_scripts+=("$cmd_name")
        tmp_dest="${TMP_SCRIPTS}/${cmd_name}"
        cp -f "$release_path" "$tmp_dest" 2>/dev/null || true
        print_diag_item "error" "  - ${cmd_name}" "Out of date (release ${LATEST_RELEASE_TAG})"
      fi
    else
      SCRIPTS_UP_TO_DATE=false
      out_of_date_scripts+=("$cmd_name")
      tmp_dest="${TMP_SCRIPTS}/${cmd_name}"
      cp -f "$release_path" "$tmp_dest" 2>/dev/null || true
      print_diag_item "error" "  - ${cmd_name}" "Not Installed"
    fi
  done

  # Stage shared modules from the release extract for doctor sync.
  local mod_item mod_name remote_rel release_mod tmp_mod
  for mod_item in "${SHARED_MODULES[@]}"; do
    mod_name="${mod_item%%:*}"
    remote_rel="${mod_item#*:}"
    release_mod="$(_diag_release_source_path "$remote_rel")"
    [[ -n "$release_mod" && -f "$release_mod" ]] || continue
    tmp_mod="${TMP_SCRIPTS}/mod_$(basename "$mod_name")"
    cp -f "$release_mod" "$tmp_mod" 2>/dev/null || true
  done
}

