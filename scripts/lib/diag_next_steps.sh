# shellcheck shell=bash
# Actionable next-step hints for diagnostics and doctor
print_package_upgrade_hint() {
  if [[ -n "${HELPERS_CHECKOUT:-}" && -d "${HELPERS_CHECKOUT}/packaging" ]]; then
    echo -e "  ${YELLOW}cd ${HELPERS_CHECKOUT}/packaging && makepkg -si${NC}"
  fi
  echo -e "  ${YELLOW}sudo pacman -Syu millennium-helpers-git${NC}"
}

print_diag_next_steps() {
  local issues=0
  local suggestions=()

  [[ "${BINARIES_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium upgrade --force        # repair/reinstall Millennium binaries"); }
  [[ "${HOOKS_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium repair                # restore bootstrap hooks"); }
  [[ "${FLATPAK_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("flatpak override --user --filesystem=/usr/lib/millennium com.valvesoftware.Steam"); }
  [[ "${PERMISSIONS_OK:-true}" == "true" && "${SKINS_DIR_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium repair                # fix ownership / skins directory"); }
  [[ "${SUDOERS_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("sudo ./install.sh install        # restore passwordless sudoers drop-in"); }
  [[ "${TIMER_ACTIVE:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("millennium schedule enable       # enable daily auto-updates"); }
  [[ "${LINGER_OK:-true}" == "true" ]] || { ((issues++)) || true; suggestions+=("sudo loginctl enable-linger ${RUNNING_USER:-$USER}  # keep user timers after logout"); }

  [[ "${MIXED_INSTALL_OK:-true}" == "true" ]] || {
    ((issues++)) || true
    suggestions+=("Resolve mixed pacman/manual helper installs before upgrading")
    if [[ -n "${HELPERS_CHECKOUT:-}" ]]; then
      suggestions+=("cd ${HELPERS_CHECKOUT}/packaging && makepkg -si  # rebuild from checkout")
    fi
    suggestions+=("sudo pacman -Syu millennium-helpers-git  # upgrade packaged helpers")
  }

  [[ "${UNMANAGED_FILES_OK:-true}" == "true" ]] || {
    ((issues++)) || true
    suggestions+=("millennium doctor                # remove unmanaged files blocking pacman")
  }

  [[ "${SCRIPTS_UP_TO_DATE:-true}" == "true" ]] || {
    ((issues++)) || true
    if [[ "${INSTALL_METHOD:-}" == "pacman" ]] || helpers_are_pacman_packaged 2>/dev/null; then
      if [[ -n "${HELPERS_CHECKOUT:-}" ]]; then
        suggestions+=("cd ${HELPERS_CHECKOUT}/packaging && makepkg -si  # rebuild from checkout")
      fi
      suggestions+=("sudo pacman -Syu millennium-helpers-git  # upgrade packaged helpers")
    else
      suggestions+=("millennium doctor                # update helper scripts")
    fi
  }

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
  local seen="|"
  for s in "${suggestions[@]}"; do
    [[ "$seen" == *"|${s}|"* ]] && continue
    seen+="${s}|"
    echo -e "  • ${s}"
  done
  echo -e "\nOr run ${GREEN}millennium doctor${NC} (alias: sudo millennium-diag doctor) to attempt automatic repairs."
}
