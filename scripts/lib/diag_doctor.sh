# shellcheck shell=bash
# shellcheck disable=SC2154 # globals initialized by millennium-diag.sh before doctor runs
# Doctor auto-repair orchestrator for millennium-diag.sh
run_doctor_repairs() {
  echo -e "\n${BLUE}=== Running Millennium Doctor (Automatic Repairs) ===${NC}"

  if [[ "$FORCE_REPAIR" != "true" ]]; then
    if [[ "$BINARIES_OK" == true && "$HOOKS_OK" == true && "$FLATPAK_OK" == true && "$SUDOERS_OK" == true && "$TIMER_ACTIVE" == true && "$LINGER_OK" == true && "$SCRIPTS_UP_TO_DATE" == true && "$PERMISSIONS_OK" == true && "$SKINS_DIR_OK" == true && "$COMPLETIONS_OK" == true && "$CLEAN_OF_OBSOLETE" == true && "$UNMANAGED_FILES_OK" == true && "$MIXED_INSTALL_OK" == true ]]; then
      echo -e "${GREEN}No issues detected. Your Millennium installation is healthy!${NC}"
      exit 0
    fi
  else
    echo -e "${YELLOW}Force option specified. Forcing all doctor repairs...${NC}"
    BINARIES_OK=false
    HOOKS_OK=false
    FLATPAK_OK=false
    TIMER_ACTIVE=false
    LINGER_OK=false
    SCRIPTS_UP_TO_DATE=false
    PERMISSIONS_OK=false
    COMPLETIONS_OK=false
    CLEAN_OF_OBSOLETE=false
    UNMANAGED_FILES_OK=false
  fi

  relaunch_steam_after_doctor=false
  if [[ "$STEAM_RUNNING" == true ]] && [[ "$BINARIES_OK" == false || "$HOOKS_OK" == false ]]; then
    if is_game_running; then
      echo -e "${RED}Error: A Steam game is currently running. Doctor repairs cannot proceed while a game is active.${NC}" >&2
      print_game_running_tip "run doctor"
      exit 1
    fi

    echo -e "${YELLOW}Steam is currently running and must be closed to apply repairs to hooks/binaries.${NC}"

    if [[ "$DRY_RUN" == "false" ]]; then
      capture_steam_env "$RUNNING_USER"
      confirm_close_steam "$RUNNING_USER" "${ASSUME_YES:-false}" || exit 1
    else
      echo -e "${YELLOW}[DRY RUN] Would capture Steam's environment and close it to apply repairs.${NC}"
    fi

    STEAM_RUNNING=false
    relaunch_steam_after_doctor=true
  fi

  # Cleanup first so package upgrades are not blocked by leftovers.
  doctor_cleanup_package_blockers
  doctor_update_helper_scripts
  doctor_repair_runtime
  doctor_repair_completions

  if [[ "$UNMANAGED_FILES_OK" == false ]] || { [[ "$SCRIPTS_UP_TO_DATE" == false ]] && { [[ "$INSTALL_METHOD" == "pacman" ]] || helpers_are_pacman_packaged; }; }; then
    echo -e "\nAfter cleanup, upgrade/reinstall the package if needed:"
    print_package_upgrade_hint
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "\n${GREEN}Doctor dry-run simulation finished successfully!${NC}"
  else
    echo -e "\n${GREEN}Doctor repairs applied successfully.${NC}"
    echo -e "Channel: ${UPDATE_CHANNEL}. Re-run ${YELLOW}millennium-diag${NC} to verify, or ${YELLOW}millennium-diag doctor${NC} again if issues remain."
  fi

  if [[ "$relaunch_steam_after_doctor" == "true" ]]; then
    echo -e "\n${GREEN}Relaunching Steam...${NC}"

    if [[ "$DRY_RUN" == "true" ]]; then
      execute relaunch_steam "$RUNNING_USER"
    else
      relaunch_steam "$RUNNING_USER"
      echo -e "${GREEN}Steam relaunched.${NC}"
    fi
  fi
}
