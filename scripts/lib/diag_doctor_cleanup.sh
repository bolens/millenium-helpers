# shellcheck shell=bash
# shellcheck disable=SC2154 # globals initialized by millennium-diag.sh before doctor runs
# Doctor cleanup: unmanaged leftovers, obsolete files, mixed-install guidance
doctor_cleanup_package_blockers() {
# Issue 0a: Unmanaged leftovers that block pacman upgrades (before any upgrade hints)
if [[ "$UNMANAGED_FILES_OK" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Removing unmanaged files that block package upgrades...${NC}"
  for f in ${unmanaged_files_found[@]+"${unmanaged_files_found[@]}"}; do
    [[ -n "$f" ]] || continue
    parent_dir=$(dirname "$f")
    if [[ -w "$parent_dir" ]] || [[ "$(id -u)" -eq 0 ]]; then
      echo "Removing unmanaged file: $f"
      execute rm -f "$f"
    else
      echo -e "${RED}Warning: Directory '${parent_dir}' is not writable. Skipping removal of ${f}.${NC}"
      echo -e "Re-run with sudo: ${YELLOW}sudo millennium-diag doctor${NC}"
    fi
  done
fi

# Issue 0b: Cleanup of obsolete / deprecated files
if [[ "$CLEAN_OF_OBSOLETE" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Cleaning up obsolete / deprecated legacy files...${NC}"
  for f in ${obsolete_files_found[@]+"${obsolete_files_found[@]}"}; do
    [[ -n "$f" ]] || continue
    parent_dir=$(dirname "$f")
    if [[ -w "$parent_dir" ]] || [[ "$(id -u)" -eq 0 ]]; then
      echo "Removing deprecated file: $f"
      execute rm -f "$f"
    else
      echo -e "${RED}Warning: Directory '${parent_dir}' is not writable. Skipping removal of ${f}.${NC}"
    fi
  done
fi

# Issue 0c: Mixed install layout guidance
if [[ "$MIXED_INSTALL_OK" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Mixed pacman and manual helper installs detected.${NC}"
  echo -e "Remove leftover /usr/local copies (or uninstall the package), then reinstall from one source:"
  print_package_upgrade_hint
  echo -e "  ${YELLOW}sudo rm -f /usr/local/bin/millennium /usr/local/bin/millennium-*${NC}"
  echo -e "  ${YELLOW}sudo rm -rf /usr/local/lib/millennium-helpers${NC}"
fi

}
