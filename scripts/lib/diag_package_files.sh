# shellcheck shell=bash
# shellcheck disable=SC2034 # status globals read by millennium-diag.sh / doctor
# Unmanaged package leftovers and obsolete legacy files
check_unmanaged_package_files() {
  UNMANAGED_FILES_OK=true
  unmanaged_files_found=()

  if [[ -n "${DIAG_TEST_UNMANAGED_LIST:-}" ]]; then
    echo -e "\nUnmanaged Package Files:"
    local unmanaged_list=()
    IFS=',' read -r -a unmanaged_list <<< "$DIAG_TEST_UNMANAGED_LIST"
    local f
    for f in ${unmanaged_list[@]+"${unmanaged_list[@]}"}; do
      [[ -n "$f" ]] || continue
      if [[ -e "$f" || -L "$f" ]]; then
        unmanaged_files_found+=("$f")
      fi
    done
    if [[ ${#unmanaged_files_found[@]} -gt 0 ]]; then
      UNMANAGED_FILES_OK=false
      print_diag_item "warn" "Unmanaged leftovers" "Detected ${#unmanaged_files_found[@]} file(s) that can block pacman upgrades"
    else
      print_diag_item "ok" "Unmanaged leftovers" "None detected"
    fi
    return
  fi

  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    return
  fi

  if ! helpers_are_pacman_packaged; then
    return
  fi

  echo -e "\nUnmanaged Package Files:"
  local candidates=(
    /usr/share/fish/vendor_completions.d/millennium.fish
    /usr/share/fish/vendor_completions.d/millennium-repair.fish
    /usr/share/fish/vendor_completions.d/millennium-upgrade.fish
    /usr/share/fish/vendor_completions.d/millennium-schedule.fish
    /usr/share/fish/vendor_completions.d/millennium-purge.fish
    /usr/share/fish/vendor_completions.d/millennium-diag.fish
    /usr/share/fish/vendor_completions.d/millennium-theme.fish
    /usr/share/fish/vendor_completions.d/millennium-mcp.fish
    /usr/share/bash-completion/completions/millennium
    /usr/share/bash-completion/completions/millennium-helpers
    /usr/share/bash-completion/completions/millennium-repair
    /usr/share/bash-completion/completions/millennium-upgrade
    /usr/share/bash-completion/completions/millennium-schedule
    /usr/share/bash-completion/completions/millennium-purge
    /usr/share/bash-completion/completions/millennium-diag
    /usr/share/bash-completion/completions/millennium-theme
    /usr/share/bash-completion/completions/millennium-mcp
    /usr/share/zsh/site-functions/_millennium
    /usr/share/zsh/site-functions/_millennium-helpers
    /usr/share/zsh/site-functions/_millennium-repair
    /usr/share/zsh/site-functions/_millennium-upgrade
    /usr/share/zsh/site-functions/_millennium-schedule
    /usr/share/zsh/site-functions/_millennium-purge
    /usr/share/zsh/site-functions/_millennium-diag
    /usr/share/zsh/site-functions/_millennium-theme
    /usr/share/zsh/site-functions/_millennium-mcp
    /usr/share/nushell/completions/millennium-helpers.nu
    /usr/share/man/man1/millennium.1
    /usr/share/man/man1/millennium-repair.1
    /usr/share/man/man1/millennium-upgrade.1
    /usr/share/man/man1/millennium-schedule.1
    /usr/share/man/man1/millennium-purge.1
    /usr/share/man/man1/millennium-diag.1
    /usr/share/man/man1/millennium-theme.1
    /usr/share/man/man1/millennium-mcp.1
  )

  local f
  for f in "${candidates[@]}"; do
    [[ -e "$f" || -L "$f" ]] || continue
    if ! pacman -Qo "$f" >/dev/null 2>&1; then
      unmanaged_files_found+=("$f")
      print_diag_item "warn" "  - $(basename "$f")" "Exists but not owned by pacman"
    fi
  done

  if [[ ${#unmanaged_files_found[@]} -gt 0 ]]; then
    UNMANAGED_FILES_OK=false
    print_diag_item "warn" "Package file ownership" "Unmanaged leftovers will block pacman -U / upgrades"
  else
    print_diag_item "ok" "Package file ownership" "No unmanaged leftovers"
  fi
}

check_obsolete_files() {
  echo -e "\nObsolete / Deprecated Legacy Files:"
  local obsolete_list=()
  # When DIAG_TEST_OBSOLETE_LIST is set (even to ""), use it — empty means "no candidates".
  if [[ "${DIAG_TEST_OBSOLETE_LIST+x}" == "x" ]]; then
    if [[ -n "$DIAG_TEST_OBSOLETE_LIST" ]]; then
      IFS=',' read -r -a obsolete_list <<< "$DIAG_TEST_OBSOLETE_LIST"
    fi
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
      "/usr/lib/millennium-helpers/lib/diag_report.sh"
      "/usr/local/lib/millennium-helpers/lib/diag_report.sh"
    )
  fi

  local found_any=false
  local f
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
