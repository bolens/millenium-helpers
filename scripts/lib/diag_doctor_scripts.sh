# shellcheck shell=bash
# shellcheck disable=SC2154 # globals initialized by millennium-diag.sh before doctor runs
# Doctor helper-script and shared-lib updates (manual + packaged hints)
doctor_update_helper_scripts() {
if [[ "$SCRIPTS_UP_TO_DATE" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Updating helper scripts...${NC}"
  if [[ "$INSTALL_METHOD" == "pacman" ]] || helpers_are_pacman_packaged; then
    echo -e "Helpers are installed via pacman. Skipping direct overwrites of package files."
    echo -e "Upgrade the package instead:"
    print_package_upgrade_hint

    if [[ -n "${HELPERS_CHECKOUT:-}" && -d "${HELPERS_CHECKOUT}/packaging/millennium-helpers-git" ]]; then
      if [[ "${ASSUME_YES:-false}" == "true" && "$DRY_RUN" == "false" ]]; then
        echo -e "Running makepkg -si from ${HELPERS_CHECKOUT}/packaging/millennium-helpers-git ..."
        if [[ "$(id -u)" -eq 0 ]]; then
          execute runuser -u "${RUNNING_USER}" -- bash -lc "cd '${HELPERS_CHECKOUT}/packaging/millennium-helpers-git' && makepkg -si --noconfirm"
        else
          execute bash -lc "cd '${HELPERS_CHECKOUT}/packaging/millennium-helpers-git' && makepkg -si --noconfirm"
        fi
      else
        echo -e "Tip: re-run with ${YELLOW}--yes${NC} to run makepkg -si automatically from the checkout."
      fi
    fi
  elif [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}Error: Root privileges are required to update helper scripts.${NC}" >&2
    echo -e "Please re-run the doctor with sudo: ${YELLOW}sudo $(basename "$0") doctor${NC}" >&2
  elif [[ "${ASSUME_YES:-false}" != "true" && "$DRY_RUN" == "false" ]]; then
    echo -e "${YELLOW}Helper scripts are out of date. Overwriting root-owned binaries requires confirmation.${NC}"
    echo -e "Re-run with ${YELLOW}--yes${NC}: ${YELLOW}sudo $(basename "$0") doctor --yes${NC}"
  else
    # Ensure release extract is available (single tarball sync).
    if [[ -z "${DIAG_RELEASE_EXTRACT:-}" || ! -d "${DIAG_RELEASE_EXTRACT}" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "[DRY RUN] Would download latest release tarball (${LATEST_RELEASE_TAG:-latest})"
      else
        fetch_latest_release_tag || true
        if ! diag_fetch_release_tarball; then
          echo -e "${RED}Error: Could not download/verify helpers release tarball; refusing to overwrite scripts.${NC}" >&2
          return 1
        fi
      fi
    fi
    if [[ -z "${TMP_SCRIPTS:-}" || ! -d "${TMP_SCRIPTS}" ]]; then
      TMP_SCRIPTS=$(mktemp -d)
    fi

    for cmd_name in ${out_of_date_scripts[@]+"${out_of_date_scripts[@]}"}; do
      [[ -n "$cmd_name" ]] || continue
      tmp_src="${TMP_SCRIPTS}/${cmd_name}"
      if [[ ! -f "$tmp_src" && -n "${DIAG_RELEASE_EXTRACT:-}" ]]; then
        for item in "${UTILITIES[@]}"; do
          if [[ "${item%%:*}" == "$cmd_name" ]]; then
            release_src="$(_diag_release_source_path "${item#*:}" || true)"
            [[ -n "$release_src" && -f "$release_src" ]] && cp -f "$release_src" "$tmp_src"
            break
          fi
        done
      fi
      dest_path="/usr/local/bin/${cmd_name}"
      if [[ -f "/usr/bin/${cmd_name}" ]]; then
        dest_path="/usr/bin/${cmd_name}"
      fi
      if [[ -f "$tmp_src" ]]; then
        echo "Updating script: ${dest_path}"
        execute install -m755 "$tmp_src" "$dest_path"
        execute chown root:root "$dest_path"
      else
        echo -e "${YELLOW}Warning: no staged copy of ${cmd_name}; skipping.${NC}"
      fi
    done

    # Keep shared libs aligned with scripts (prevents function skew like sysctl_user).
    helper_lib_dir=""
    if [[ -d /usr/local/lib/millennium-helpers ]]; then
      helper_lib_dir="/usr/local/lib/millennium-helpers"
    elif [[ -d /usr/lib/millennium-helpers ]]; then
      helper_lib_dir="/usr/lib/millennium-helpers"
    fi
    if [[ -n "$helper_lib_dir" ]]; then
      echo "Syncing shared library modules in ${helper_lib_dir}..."
      execute mkdir -p "${helper_lib_dir}/lib"
      for item in "${SHARED_MODULES[@]}"; do
        mod_name="${item%%:*}"
        remote_rel="${item#*:}"
        tmp_mod="${TMP_SCRIPTS}/mod_$(basename "$mod_name")"
        if [[ ! -f "$tmp_mod" && -n "${DIAG_RELEASE_EXTRACT:-}" ]]; then
          release_mod="$(_diag_release_source_path "$remote_rel" || true)"
          [[ -n "$release_mod" && -f "$release_mod" ]] && cp -f "$release_mod" "$tmp_mod"
        fi
        dest_mod="${helper_lib_dir}/${mod_name}"
        if [[ "$DRY_RUN" == "true" ]]; then
          echo -e "[DRY RUN] Would install ${remote_rel} to ${dest_mod}"
        elif [[ -f "$tmp_mod" ]]; then
          echo "Updating module: ${dest_mod}"
          execute install -m644 "$tmp_mod" "$dest_mod"
          execute chown root:root "$dest_mod"
        else
          echo -e "${YELLOW}Warning: could not stage ${remote_rel}; skipping.${NC}"
        fi
      done

      # Refresh install-meta for the same helpers track (do not jump pins).
      if [[ "$DRY_RUN" != "true" ]] && declare -F write_helpers_install_meta >/dev/null 2>&1; then
        local meta_track="${HELPERS_TRACK:-release}"
        local meta_ref="${HELPERS_TRACK_REF:-}"
        local meta_ver=""
        local meta_url=""
        case "$meta_track" in
          tag)
            meta_ver="${meta_ref#v}"
            _meta_arch=amd64
            case "$(uname -m 2>/dev/null || echo x86_64)" in aarch64 | arm64) _meta_arch=arm64 ;; esac
            meta_url="https://github.com/bolens/millenium-helpers/releases/download/${meta_ref}/millennium-helpers-v${meta_ver}-linux-${_meta_arch}.tar.gz"
            ;;
          main)
            meta_ref="${meta_ref:-main}"
            meta_url="https://github.com/bolens/millenium-helpers/archive/refs/heads/main.tar.gz"
            ;;
          *)
            meta_ref="${LATEST_RELEASE_TAG:-${meta_ref:-latest}}"
            meta_ver="${LATEST_RELEASE_VERSION:-${meta_ref#v}}"
            if [[ -n "${LATEST_RELEASE_TAG:-}" ]]; then
              _meta_arch=amd64
              case "$(uname -m 2>/dev/null || echo x86_64)" in aarch64 | arm64) _meta_arch=arm64 ;; esac
              meta_url="https://github.com/bolens/millenium-helpers/releases/download/${LATEST_RELEASE_TAG}/millennium-helpers-v${meta_ver}-linux-${_meta_arch}.tar.gz"
            fi
            ;;
        esac
        if [[ -f "${helper_lib_dir}/VERSION" ]]; then
          meta_ver="$(tr -d '[:space:]' < "${helper_lib_dir}/VERSION" || true)"
        fi
        write_helpers_install_meta "$helper_lib_dir" "$meta_track" "$meta_ref" "$meta_ver" "$meta_url" "" || true
      fi
    fi
    echo -e "${GREEN}Helper scripts successfully updated!${NC}"
  fi
fi

}
