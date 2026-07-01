#!/usr/bin/env bash
# Installation/uninstallation script for Millennium helper scripts.
set -euo pipefail

TARGET_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDOERS_FILE="/etc/sudoers.d/millennium-helpers"

# Source shared helpers (color vars, execute, write_file)
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/scripts/common.sh"

# Define scripts to manage (format: "source_filename:target_command_name")
SCRIPTS=(
  "scripts/millennium-repair.sh:millennium-repair"
  "scripts/millennium-upgrade-beta.sh:millennium-upgrade-beta"
  "scripts/millennium-upgrade-stable.sh:millennium-upgrade-stable"
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
    echo -e "${RED}Error: This script must be run with sudo to install system-wide to ${TARGET_DIR}.${NC}" >&2
    echo -e "Please run: sudo $0 ${ORIGINAL_ARGS[*]}" >&2
    exit 1
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
  echo -e "${BLUE}Installing shell autocompletions...${NC}"

  # 1. Bash Completions
  local bash_dir="/usr/share/bash-completion/completions"
  if [[ -d "$bash_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Installing Bash completions... "
    if execute mkdir -p "$bash_dir" && \
       execute cp -f "${SCRIPT_DIR}/completions/bash/millennium-helpers" "$bash_dir/millennium-helpers" && \
       execute chmod 644 "$bash_dir/millennium-helpers" && \
       execute chown root:root "$bash_dir/millennium-helpers"; then
      local symlinks_ok=true
      for item in "${SCRIPTS[@]}"; do
        local dest="${item#*:}"
        execute ln -sf "millennium-helpers" "${bash_dir}/${dest}" || symlinks_ok=false
      done
      if [[ "$symlinks_ok" == "true" ]]; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL (symlinks)${NC}"
        exit 1
      fi
    else
      echo -e "${RED}FAIL${NC}"
      exit 1
    fi
  fi

  # 2. Zsh Completions
  local zsh_dir="/usr/share/zsh/site-functions"
  if [[ -d "$zsh_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Installing Zsh completions... "
    if execute mkdir -p "$zsh_dir" && \
       execute cp -f "${SCRIPT_DIR}/completions/zsh/_millennium-helpers" "$zsh_dir/_millennium-helpers" && \
       execute chmod 644 "$zsh_dir/_millennium-helpers" && \
       execute chown root:root "$zsh_dir/_millennium-helpers"; then
      local symlinks_ok=true
      for item in "${SCRIPTS[@]}"; do
        local dest="${item#*:}"
        execute ln -sf "_millennium-helpers" "${zsh_dir}/_${dest}" || symlinks_ok=false
      done
      if [[ "$symlinks_ok" == "true" ]]; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL (symlinks)${NC}"
        exit 1
      fi
    else
      echo -e "${RED}FAIL${NC}"
      exit 1
    fi
  fi

  # 3. Fish Completions
  local fish_dir="/usr/share/fish/vendor_completions.d"
  if [[ -d "$fish_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Installing Fish completions... "
    local fish_ok=true
    execute mkdir -p "$fish_dir" || fish_ok=false
    if [[ "$fish_ok" == "true" ]]; then
      for file in "${SCRIPT_DIR}/completions/fish/"*.fish; do
        [[ -f "$file" ]] || continue
        if ! (execute cp -f "$file" "$fish_dir/" && \
              execute chmod 644 "${fish_dir}/$(basename "$file")" && \
              execute chown root:root "${fish_dir}/$(basename "$file")"); then
          fish_ok=false
        fi
      done
    fi
    if [[ "$fish_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      exit 1
    fi
  fi

  # 4. Nushell Completions
  for base_dir in "/usr/share" "/usr/local/share"; do
    local cand_dir="${base_dir}/nushell/completions"
    if [[ -d "${base_dir}/nushell" || "$DRY_RUN" == "true" ]]; then
      printf "Installing Nushell completions to %s... " "${cand_dir}"
      if execute mkdir -p "$cand_dir" && \
         execute cp -f "${SCRIPT_DIR}/completions/nushell/millennium-helpers.nu" "$cand_dir/millennium-helpers.nu" && \
         execute chmod 644 "$cand_dir/millennium-helpers.nu" && \
         execute chown root:root "$cand_dir/millennium-helpers.nu"; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL${NC}"
        exit 1
      fi
    fi
  done
}

install_scripts() {
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
       execute chown root:root "$dest_path" && \
       execute chmod 755 "$dest_path"; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      exit 1
    fi
  done

  # Copy shared helper library
  local lib_dir="/usr/local/lib/millennium-helpers"
  printf "Installing shared helper library to %s... " "${lib_dir}/common.sh"
  if execute mkdir -p "$lib_dir" && \
     execute cp -f "${SCRIPT_DIR}/scripts/common.sh" "${lib_dir}/common.sh" && \
     execute chown -R root:root "$lib_dir" && \
     execute chmod 755 "$lib_dir" && \
     execute chmod 644 "${lib_dir}/common.sh"; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    exit 1
  fi

  install_completions

  # Configure passwordless sudoers rules in /etc/sudoers.d/millennium-helpers
  local user_name="${SUDO_USER:-$USER}"
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
${user_name} ALL=(ALL) NOPASSWD: /usr/local/bin/millennium-upgrade-stable, /usr/local/bin/millennium-upgrade-beta, /usr/local/bin/millennium-diag, /usr/local/bin/millennium-purge, /usr/local/bin/millennium-repair
EOF
      
      execute chmod 440 "$SUDOERS_FILE" || sudo_ok=false
      execute chown root:root "$SUDOERS_FILE" || sudo_ok=false

      # Validate sudoers configuration with visudo
      if [[ "$DRY_RUN" == "false" ]]; then
        if visudo -cf "$SUDOERS_FILE" &>/dev/null; then
          if command -v restorecon &>/dev/null; then
            restorecon "$SUDOERS_FILE" || true
          fi
        else
          sudo_ok=false
          rm -f "$SUDOERS_FILE"
        fi
      fi
    fi
    
    if [[ "$sudo_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      exit 1
    fi
  else
    echo -e "${YELLOW}Running as root directly. Skipping passwordless sudo configuration.${NC}"
  fi

  # Clean up legacy local user symlinks if they exist
  local user_home
  user_home="$(getent passwd "$user_name" | cut -d: -f6)"
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
  echo -e "${BLUE}Uninstalling shell autocompletions...${NC}"

  # 1. Bash Completions
  local bash_dir="/usr/share/bash-completion/completions"
  if [[ -d "$bash_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing Bash completions... "
    local remove_ok=true
    execute rm -f "$bash_dir/millennium-helpers" || remove_ok=false
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      execute rm -f "${bash_dir}/${dest}" || remove_ok=false
    done
    if [[ "$remove_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  # 2. Zsh Completions
  local zsh_dir="/usr/share/zsh/site-functions"
  if [[ -d "$zsh_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing Zsh completions... "
    local remove_ok=true
    execute rm -f "$zsh_dir/_millennium-helpers" || remove_ok=false
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      execute rm -f "${zsh_dir}/_${dest}" || remove_ok=false
    done
    if [[ "$remove_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  # 3. Fish Completions
  local fish_dir="/usr/share/fish/vendor_completions.d"
  if [[ -d "$fish_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing Fish completions... "
    local remove_ok=true
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      execute rm -f "${fish_dir}/${dest}.fish" || remove_ok=false
    done
    if [[ "$remove_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  # 4. Nushell Completions
  for base_dir in "/usr/share" "/usr/local/share"; do
    local cand_dir="${base_dir}/nushell/completions"
    if [[ -d "$cand_dir" || "$DRY_RUN" == "true" ]]; then
      printf "Removing Nushell completions from %s... " "${cand_dir}"
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
    fi
  fi

  if [[ -f "$SUDOERS_FILE" || "$DRY_RUN" == "true" ]]; then
    printf "Removing: %s... " "$SUDOERS_FILE"
    if execute rm -f "$SUDOERS_FILE"; then
      echo -e "${GREEN}OK${NC}"
      removed_any=true
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  uninstall_completions
  removed_any=true

  # Clean up systemd user timers/services for the invoking user
  local user_name="${SUDO_USER:-$USER}"
  if [[ "$user_name" != "root" ]]; then
    local user_home
    user_home="$(getent passwd "$user_name" | cut -d: -f6)"
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
    install_scripts
    ;;
  uninstall)
    uninstall_scripts
    ;;
esac
