#!/usr/bin/env bash
# Installation/uninstallation script for Millennium helper scripts.
set -euo pipefail

TARGET_DIR="${TARGET_DIR:-/usr/local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If running standalone/piped (e.g. curl ... | bash), download the full repo to a temp folder and run
if [[ ! -f "${SCRIPT_DIR}/scripts/common.sh" ]]; then
  echo "Running in standalone/piped mode. Downloading repository..."
  TEMP_DIR=$(mktemp -d)
  if [[ -z "$TEMP_DIR" || ! -d "$TEMP_DIR" ]]; then
    echo "Error: Failed to create temporary directory for standalone installation." >&2
    exit 1
  fi
  # Best-effort cleanup
  trap 'rm -rf "$TEMP_DIR"' EXIT
  
  download_ok=false
  if command -v curl >/dev/null 2>&1; then
    if curl -sSL https://github.com/bolens/millenium-helpers/archive/refs/heads/main.tar.gz | tar -xz -C "$TEMP_DIR" --strip-components=1; then
      download_ok=true
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -qO- https://github.com/bolens/millenium-helpers/archive/refs/heads/main.tar.gz | tar -xz -C "$TEMP_DIR" --strip-components=1; then
      download_ok=true
    fi
  else
    echo "Error: curl or wget is required for standalone installation." >&2
    exit 1
  fi

  if [[ "$download_ok" == "false" ]]; then
    echo "Error: Failed to download and extract the installation repository from GitHub." >&2
    exit 1
  fi
  
  # Run the installer from the temp directory with the original arguments
  bash "$TEMP_DIR/install.sh" "$@"
  exit 0
fi

SUDOERS_FILE="${MOCK_SUDOERS_FILE:-/etc/sudoers.d/millennium-helpers}"

# Source shared helpers (color vars, execute, write_file)
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/scripts/common.sh"

# Define scripts to manage (format: "source_filename:target_command_name")
SCRIPTS=(
  "scripts/millennium-repair.sh:millennium-repair"
  "scripts/millennium-upgrade.sh:millennium-upgrade"
  "scripts/millennium-schedule.sh:millennium-schedule"
  "scripts/millennium-purge.sh:millennium-purge"
  "scripts/millennium-diag.sh:millennium-diag"
  "scripts/millennium-theme.sh:millennium-theme"
  "scripts/millennium-mcp.py:millennium-mcp"
)

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS] [COMMAND]

Commands:
  install      Install scripts to ${TARGET_DIR} (default, requires sudo)
  uninstall    Remove scripts from ${TARGET_DIR} (requires sudo)

Options:
  -d, --dry-run      Perform dry-run without copying files or configuring sudoers
  -i, --install      Perform installation
  -u, --uninstall    Perform uninstallation
  -p, --purge        During uninstall, also purge all Millennium client files/hooks
  -h, --help         Show this help message
EOF
}

check_root() {
  if [[ "$DRY_RUN" == "false" ]] && [[ "$(id -u)" -ne 0 ]]; then
    if [[ "$(uname)" == "Darwin" && -w "$TARGET_DIR" ]]; then
      return 0
    fi
    echo -e "${RED}Error: This script must be run with sudo to install system-wide to ${TARGET_DIR}.${NC}" >&2
    echo -e "Please run: sudo $0 ${ORIGINAL_ARGS[*]}" >&2
    exit 1
  fi
}

change_owner() {
  local recursive=""
  if [[ "$1" == "-R" ]]; then
    recursive="-R"
    shift
  fi
  local target="$1"
  local owner="${2:-root:root}"
  if [[ "$(id -u)" -eq 0 ]]; then
    if [[ "$(uname)" == "Darwin" && "$owner" == "root:root" ]]; then
      owner="root:wheel"
    fi
    if [[ -n "$recursive" ]]; then
      execute chown -R "$owner" "$target"
    else
      execute chown "$owner" "$target"
    fi
  fi
}

# Parse arguments
ORIGINAL_ARGS=("$@")
ACTION="install"
DRY_RUN=false
PURGE_REQUESTED=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    install|-i|--install)
      ACTION="install"
      shift
      ;;
    uninstall|-u|--uninstall)
      ACTION="uninstall"
      shift
      ;;
    -p|--purge)
      PURGE_REQUESTED=true
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown argument: $1${NC}" >&2
      show_help
      exit 1
      ;;
  esac
done

check_root "$ACTION"

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}=== DRY RUN MODE: No changes will be made ===${NC}"
fi

install_completions() {
  # Clean up obsolete completions from older installations
  local obsolete_completions=("millennium-upgrade-stable" "millennium-upgrade-beta")
  local user_name="${SUDO_USER:-$(id -un)}"
  local USER_HOME
  USER_HOME="$(get_user_home "$user_name")"
  
  local base_bash_dir="/usr/share/bash-completion/completions"
  local base_zsh_dir="/usr/share/zsh/site-functions"
  local base_fish_dir="/usr/share/fish/vendor_completions.d"
  local base_nu_dirs=("/usr/share/nushell/completions" "/usr/local/share/nushell/completions")

  if [[ "$(uname)" == "Darwin" ]]; then
    local brew_prefix="/opt/homebrew"
    if command -v brew &>/dev/null; then
      brew_prefix="$(brew --prefix)"
    fi
    base_bash_dir="${brew_prefix}/etc/bash_completion.d"
    base_zsh_dir="${brew_prefix}/share/zsh/site-functions"
    base_fish_dir="${brew_prefix}/share/fish/vendor_completions.d"
    base_nu_dirs=("${brew_prefix}/share/nushell/completions" "${USER_HOME}/.config/nushell/completions")
  fi

  for comp in "${obsolete_completions[@]}"; do
    local f="${base_bash_dir}/${comp}"
    if [[ -f "$f" && -w "$base_bash_dir" ]]; then
      execute rm -f "$f"
    fi
  done

  # Also clean up from local share directories
  for base_dir in "/usr/share" "/usr/local/share"; do
    local obsolete_zsh="${base_dir}/zsh/site-functions"
    for comp in "${obsolete_completions[@]}"; do
      local f="${obsolete_zsh}/_${comp}"
      if [[ -f "$f" && -w "$obsolete_zsh" ]]; then
        execute rm -f "$f"
      fi
    done
    local obsolete_fish="${base_dir}/fish/vendor_completions.d"
    for comp in "${obsolete_completions[@]}"; do
      local f="${obsolete_fish}/${comp}.fish"
      if [[ -f "$f" && -w "$obsolete_fish" ]]; then
        execute rm -f "$f"
      fi
    done
  done

  echo -e "${BLUE}Installing shell autocompletions...${NC}"

  # 1. Bash Completions
  if [[ -d "$base_bash_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Installing Bash completions... "
    if execute mkdir -p "$base_bash_dir" && \
       execute cp -f "${SCRIPT_DIR}/completions/bash/millennium-helpers" "$base_bash_dir/millennium-helpers" && \
       execute chmod 644 "$base_bash_dir/millennium-helpers" && \
       change_owner "$base_bash_dir/millennium-helpers"; then
      local symlinks_ok=true
      for item in "${SCRIPTS[@]}"; do
        local dest="${item#*:}"
        execute ln -sf "millennium-helpers" "${base_bash_dir}/${dest}" || symlinks_ok=false
      done
      if [[ "$symlinks_ok" == "true" ]]; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL (symlinks)${NC}"
        echo -e "${RED}Error: Failed to create symlinks for some Bash completion scripts in ${base_bash_dir}.${NC}" >&2
        exit 1
      fi
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to copy or configure Bash completion base script in ${base_bash_dir}.${NC}" >&2
      exit 1
    fi
  fi

  # 2. Zsh Completions
  if [[ -d "$base_zsh_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Installing Zsh completions... "
    if execute mkdir -p "$base_zsh_dir" && \
       execute cp -f "${SCRIPT_DIR}/completions/zsh/_millennium-helpers" "$base_zsh_dir/_millennium-helpers" && \
       execute chmod 644 "$base_zsh_dir/_millennium-helpers" && \
       change_owner "$base_zsh_dir/_millennium-helpers"; then
      local symlinks_ok=true
      for item in "${SCRIPTS[@]}"; do
        local dest="${item#*:}"
        execute ln -sf "_millennium-helpers" "${base_zsh_dir}/_${dest}" || symlinks_ok=false
      done
      if [[ "$symlinks_ok" == "true" ]]; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL (symlinks)${NC}"
        echo -e "${RED}Error: Failed to create symlinks for some Zsh completion scripts in ${base_zsh_dir}.${NC}" >&2
        exit 1
      fi
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to copy or configure Zsh completion base script in ${base_zsh_dir}.${NC}" >&2
      exit 1
    fi
  fi

  # 3. Fish Completions
  if [[ -d "$base_fish_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Installing Fish completions... "
    local fish_ok=true
    execute mkdir -p "$base_fish_dir" || fish_ok=false
    if [[ "$fish_ok" == "true" ]]; then
      for file in "${SCRIPT_DIR}/completions/fish/"*.fish; do
        [[ -f "$file" ]] || continue
        if ! (execute cp -f "$file" "$base_fish_dir/" && \
              execute chmod 644 "${base_fish_dir}/$(basename "$file")" && \
              change_owner "${base_fish_dir}/$(basename "$file")"); then
          fish_ok=false
        fi
      done
    fi
    if [[ "$fish_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to copy or configure Fish completions in ${base_fish_dir}.${NC}" >&2
      exit 1
    fi
  fi

  # 4. Nushell Completions
  for cand_dir in "${base_nu_dirs[@]}"; do
    if [[ -d "$cand_dir" || "$DRY_RUN" == "true" ]]; then
      printf "Installing Nushell completions to %s... " "$cand_dir"
      if execute mkdir -p "$cand_dir" && \
         execute cp -f "${SCRIPT_DIR}/completions/nushell/millennium-helpers.nu" "$cand_dir/millennium-helpers.nu" && \
         execute chmod 644 "$cand_dir/millennium-helpers.nu" && \
         change_owner "$cand_dir/millennium-helpers.nu"; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL${NC}"
        echo -e "${RED}Error: Failed to copy or configure Nushell completions in ${cand_dir}.${NC}" >&2
      fi
    fi
  done
}

run_wizard() {
  local user_name="${SUDO_USER:-$(id -un)}"
  if [[ "$user_name" != "root" ]]; then
    local dry_flag=""
    [[ "${DRY_RUN}" == "true" ]] && dry_flag="-d"
    runuser -l "$user_name" -c "FORCE_WIZARD=true bash ${SCRIPT_DIR}/scripts/millennium-schedule.sh setup ${dry_flag}"
  fi
}

install_scripts() {
  local user_name="${SUDO_USER:-$(id -un)}"
  # Clean up obsolete script files from older installations
  local obsolete_scripts=("millennium-upgrade-stable" "millennium-upgrade-beta")
  for script in "${obsolete_scripts[@]}"; do
    local f="${TARGET_DIR}/${script}"
    if [[ -f "$f" && -w "$TARGET_DIR" ]]; then
      echo -e "${YELLOW}Removing obsolete script: ${f}${NC}"
      execute rm -f "$f"
    fi
  done

  echo -e "${BLUE}Installing Millennium helper scripts to ${TARGET_DIR}...${NC}"

  for item in "${SCRIPTS[@]}"; do
    local src="${item%%:*}"
    local dest="${item#*:}"
    local src_path="${SCRIPT_DIR}/${src}"
    local dest_path="${TARGET_DIR}/${dest}"

    if [[ ! -f "$src_path" ]]; then
      echo -e "${RED}Error: Source script not found: ${src_path}${NC}" >&2
      exit 1
    fi

    # Copy script, set ownership to root, and make executable (755)
    printf "Installing: %s... " "$dest_path"
    if execute cp -f "$src_path" "$dest_path" && \
       change_owner "$dest_path" && \
       execute chmod 755 "$dest_path"; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to install or configure helper script ${dest_path}.${NC}" >&2
      echo -e "${YELLOW}Please ensure you have write permissions to ${TARGET_DIR} (you may need to run this script using sudo).${NC}" >&2
      exit 1
    fi
  done

  # Copy shared helper library and its modules
  local lib_dir="/usr/local/lib/millennium-helpers"
  printf "Installing shared helper library to %s... " "${lib_dir}/common.sh"
  if execute mkdir -p "${lib_dir}/lib" && \
     execute cp -f "${SCRIPT_DIR}/scripts/common.sh" "${lib_dir}/common.sh" && \
     execute cp -f "${SCRIPT_DIR}/scripts/lib/"*.sh "${lib_dir}/lib/" && \
     change_owner -R "$lib_dir" && \
     execute chmod 755 "$lib_dir" && \
     execute chmod 755 "${lib_dir}/lib" && \
     execute chmod 644 "${lib_dir}/common.sh" && \
     execute chmod 644 "${lib_dir}/lib/"*.sh; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    echo -e "${RED}Error: Failed to copy or configure shared helper library directory ${lib_dir}.${NC}" >&2
    echo -e "${YELLOW}Please verify directory permissions for ${lib_dir}.${NC}" >&2
    exit 1
  fi

  install_completions

  # Configure passwordless sudoers rules in /etc/sudoers.d/millennium-helpers
  if [[ "$(uname)" != "Darwin" ]]; then
    if [[ "$user_name" != "root" ]]; then
      printf "Configuring passwordless sudo rule in %s... " "${SUDOERS_FILE}"
      
      local sudo_ok=true
      
      # Ensure target directory exists and has secure permissions
      local sudoers_d_dir
      sudoers_d_dir="$(dirname "$SUDOERS_FILE")"
      if [[ "$DRY_RUN" == "false" && ! -d "$sudoers_d_dir" ]]; then
        mkdir -p "$sudoers_d_dir" || sudo_ok=false
        chmod 750 "$sudoers_d_dir" || sudo_ok=false
        chown root:root "$sudoers_d_dir" || sudo_ok=false
      elif [[ "$DRY_RUN" == "true" ]]; then
        echo -e "\n${YELLOW}[DRY RUN] Would ensure directory exists with 750 permissions:${NC} ${sudoers_d_dir}"
      fi

      if [[ "$sudo_ok" == "true" ]]; then
        write_file "$SUDOERS_FILE" << EOF &>/dev/null || sudo_ok=false
# Automatically generated by Millennium helpers installer. Do not edit manually.
${user_name} ALL=(ALL) NOPASSWD: ${TARGET_DIR}/millennium-upgrade, ${TARGET_DIR}/millennium-diag, ${TARGET_DIR}/millennium-purge, ${TARGET_DIR}/millennium-repair
EOF
        
        execute chmod 440 "$SUDOERS_FILE" || sudo_ok=false
        execute chown root:root "$SUDOERS_FILE" || sudo_ok=false

        # Validate sudoers configuration with visudo
        if [[ "$DRY_RUN" == "false" ]]; then
          local visudo_err
          if visudo_err=$(visudo -cf "$SUDOERS_FILE" 2>&1); then
            if command -v restorecon &>/dev/null; then
              restorecon "$SUDOERS_FILE" || true
            fi
          elif [[ ! -t 0 && "${FORCE_RECOVERY:-}" != "true" ]]; then
            # Non-interactive terminal: log and fail
            echo -e "\n${RED}Error: visudo validation failed:${NC}" >&2
            echo "$visudo_err" >&2
            sudo_ok=false
            rm -f "$SUDOERS_FILE"
          else
            echo -e "\n${RED}Warning: visudo validation failed for the generated sudoers file:${NC}"
            echo -e "${visudo_err}"
            
            # Ask if they want to override the username or manually edit
            while true; do
              echo -e "\nWhat would you like to do?"
              echo -e "  1) Retry with a different user/group name"
              echo -e "  2) Skip sudoers configuration (continue installation without passwordless sudo)"
              echo -e "  3) Abort installation"
              read -rp "Selection [1-3, default: 3]: " choice_sel
              case "$choice_sel" in
                1)
                  local new_user=""
                  read -rp "Enter new user or group name (e.g. %wheel or custom_user): " new_user
                  if [[ -n "$new_user" ]]; then
                    # Rewrite file with new user
                    write_file "$SUDOERS_FILE" << EOF &>/dev/null
# Automatically generated by Millennium helpers installer. Do not edit manually.
${new_user} ALL=(ALL) NOPASSWD: ${TARGET_DIR}/millennium-upgrade, ${TARGET_DIR}/millennium-diag, ${TARGET_DIR}/millennium-purge, ${TARGET_DIR}/millennium-repair
EOF
                    chmod 440 "$SUDOERS_FILE"
                    chown root:root "$SUDOERS_FILE"
                    # Re-run validation
                    if visudo_err=$(visudo -cf "$SUDOERS_FILE" 2>&1); then
                      echo -e "${GREEN}Sudoers configuration validated successfully!${NC}"
                      if command -v restorecon &>/dev/null; then
                        restorecon "$SUDOERS_FILE" || true
                      fi
                      break
                    else
                      echo -e "${RED}visudo validation failed again:${NC}"
                      echo -e "${visudo_err}"
                    fi
                  fi
                  ;;
                2)
                  echo -e "${YELLOW}Skipping passwordless sudo setup. You will need to run helper scripts with root permissions manually.${NC}"
                  rm -f "$SUDOERS_FILE"
                  sudo_ok=true
                  break
                  ;;
                ""|3)
                  sudo_ok=false
                  rm -f "$SUDOERS_FILE"
                  break
                  ;;
                *)
                  echo -e "${RED}Invalid selection. Please choose 1, 2, or 3.${NC}"
                  ;;
              esac
            done
          fi
        fi
      fi
      
      if [[ "$sudo_ok" == "true" ]]; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL${NC}"
        echo -e "${RED}Error: Failed to configure or validate passwordless sudo rule in ${SUDOERS_FILE}.${NC}" >&2
        exit 1
      fi
    else
      echo -e "${YELLOW}Running as root directly. Skipping passwordless sudo configuration.${NC}"
    fi
  fi

  # Clean up legacy local user symlinks if they exist
  local user_home
  user_home="$(get_user_home "$user_name")"
  local user_bin="${user_home}/.local/bin"

  if [[ -d "$user_bin" || "$DRY_RUN" == "true" ]]; then
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      local legacy_path="${user_bin}/${dest}"
      if [[ -L "$legacy_path" || "$DRY_RUN" == "true" ]]; then
        echo "Removing legacy user symlink: $legacy_path"
        execute rm -f "$legacy_path"
      fi
    done
  fi



  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}Dry run completed successfully!${NC}"
  else
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "\nYou can now run the scripts directly from your terminal:"
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      echo -e "  - ${dest}"
    done
  fi
}

uninstall_completions() {
  local base_bash_dir="/usr/share/bash-completion/completions"
  local base_zsh_dir="/usr/share/zsh/site-functions"
  local base_fish_dir="/usr/share/fish/vendor_completions.d"
  local base_nu_dirs=("/usr/share/nushell/completions" "/usr/local/share/nushell/completions")
  local user_name="${SUDO_USER:-$(id -un)}"
  local USER_HOME
  USER_HOME="$(get_user_home "$user_name")"

  if [[ "$(uname)" == "Darwin" ]]; then
    local brew_prefix="/opt/homebrew"
    if command -v brew &>/dev/null; then
      brew_prefix="$(brew --prefix)"
    fi
    base_bash_dir="${brew_prefix}/etc/bash_completion.d"
    base_zsh_dir="${brew_prefix}/share/zsh/site-functions"
    base_fish_dir="${brew_prefix}/share/fish/vendor_completions.d"
    base_nu_dirs=("${brew_prefix}/share/nushell/completions" "${USER_HOME}/.config/nushell/completions")
  fi

  echo -e "${BLUE}Uninstalling shell autocompletions...${NC}"

  # 1. Bash Completions
  if [[ -d "$base_bash_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing Bash completions... "
    local remove_ok=true
    execute rm -f "$base_bash_dir/millennium-helpers" || remove_ok=false
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      execute rm -f "${base_bash_dir}/${dest}" || remove_ok=false
    done
    if [[ "$remove_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  # 2. Zsh Completions
  if [[ -d "$base_zsh_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing Zsh completions... "
    local remove_ok=true
    execute rm -f "$base_zsh_dir/_millennium-helpers" || remove_ok=false
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      execute rm -f "${base_zsh_dir}/_${dest}" || remove_ok=false
    done
    if [[ "$remove_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  # 3. Fish Completions
  if [[ -d "$base_fish_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing Fish completions... "
    local remove_ok=true
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      execute rm -f "${base_fish_dir}/${dest}.fish" || remove_ok=false
    done
    if [[ "$remove_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  # 4. Nushell Completions
  for cand_dir in "${base_nu_dirs[@]}"; do
    if [[ -d "$cand_dir" || "$DRY_RUN" == "true" ]]; then
      printf "Removing Nushell completions from %s... " "$cand_dir"
      if execute rm -f "${cand_dir}/millennium-helpers.nu"; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL${NC}"
      fi
    fi
  done
}

uninstall_scripts() {
  local purge_all=false
  if [[ "$PURGE_REQUESTED" == "true" ]]; then
    purge_all=true
  elif [[ -t 0 ]]; then
    # Print menu and read response if in interactive terminal
    echo -e "${YELLOW}Millennium Client Cleanup:${NC}"
    read -rp "Would you also like to completely purge all Millennium binaries, Steam hooks, and themes? [y/N]: " resp
    if [[ "$resp" =~ ^[Yy]$ ]]; then
      purge_all=true
    fi
  fi

  if [[ "$purge_all" == "true" ]]; then
    local purge_script="${SCRIPT_DIR}/scripts/millennium-purge.sh"
    if [[ -f "$purge_script" ]]; then
      echo -e "${YELLOW}Invoking Millennium purge script...${NC}"
      local dry_flag=""
      [[ "$DRY_RUN" == "true" ]] && dry_flag="--dry-run"
      execute "$purge_script" $dry_flag
    fi
  fi

  echo -e "${BLUE}Uninstalling Millennium helper scripts from ${TARGET_DIR}...${NC}"
  
  local removed_any=false
  for item in "${SCRIPTS[@]}"; do
    local dest="${item#*:}"
    local dest_path="${TARGET_DIR}/${dest}"

    if [[ -f "$dest_path" || "$DRY_RUN" == "true" ]]; then
      printf "Removing: %s... " "$dest_path"
      if execute rm -f "$dest_path"; then
        echo -e "${GREEN}OK${NC}"
        removed_any=true
      else
        echo -e "${RED}FAIL${NC}"
        echo -e "${RED}Error: Failed to remove helper script ${dest_path}.${NC}" >&2
      fi
    fi
  done

  local lib_dir="/usr/local/lib/millennium-helpers"
  if [[ -d "$lib_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing shared helper library: %s... " "${lib_dir}"
    if execute rm -rf "$lib_dir"; then
      echo -e "${GREEN}OK${NC}"
      removed_any=true
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to remove shared helper library directory ${lib_dir}.${NC}" >&2
    fi
  fi

  if [[ -f "$SUDOERS_FILE" || "$DRY_RUN" == "true" ]]; then
    printf "Removing: %s... " "$SUDOERS_FILE"
    if execute rm -f "$SUDOERS_FILE"; then
      echo -e "${GREEN}OK${NC}"
      removed_any=true
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to remove sudoers configuration file ${SUDOERS_FILE}.${NC}" >&2
    fi
  fi

  uninstall_completions
  removed_any=true

  # Clean up systemd user timers/services for the invoking user
  local user_name="${SUDO_USER:-$(id -un)}"
  if [[ "$user_name" != "root" ]]; then
    local user_home
    user_home="$(get_user_home "$user_name")"
    local user_xdg=""
    if [[ "$(id -u)" -eq 0 ]]; then
      # shellcheck disable=SC2016
      user_xdg=$(runuser -l "$user_name" -c 'echo "${XDG_CONFIG_HOME:-}"' 2>/dev/null || true)
    fi
    local user_systemd_dir
    if [[ -n "$user_xdg" ]]; then
      user_systemd_dir="${user_xdg}/systemd/user"
    else
      user_systemd_dir="${user_home}/.config/systemd/user"
    fi
    
    if [[ -d "$user_systemd_dir" || "$DRY_RUN" == "true" ]]; then
      local timer_file="${user_systemd_dir}/millennium-update.timer"
      local service_file="${user_systemd_dir}/millennium-update.service"
      
      if [[ -f "$timer_file" || -f "$service_file" || "$DRY_RUN" == "true" ]]; then
        echo "Disabling and removing systemd user update timer/service..."
        execute runuser -l "$user_name" -c "systemctl --user disable --now millennium-update.timer" || true
        execute runuser -l "$user_name" -c "systemctl --user stop millennium-update.service" || true
        
        execute rm -f "$timer_file" "$service_file"
        execute runuser -l "$user_name" -c "systemctl --user daemon-reload" || true
        removed_any=true
      fi
    fi
  fi

  if [[ "$removed_any" == true || "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}Uninstallation completed successfully!${NC}"
  else
    echo -e "${YELLOW}No installed scripts or configuration found to uninstall.${NC}"
  fi
}

case "$ACTION" in
  install)
    if [[ ( ${#ORIGINAL_ARGS[@]} -eq 0 || "${FORCE_WIZARD:-}" == "true" ) && ( -t 0 || "${FORCE_WIZARD:-}" == "true" ) ]]; then
      run_wizard
    fi
    install_scripts
    ;;
  uninstall)
    uninstall_scripts
    ;;
esac
