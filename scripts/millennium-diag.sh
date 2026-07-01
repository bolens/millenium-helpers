#!/usr/bin/env bash
# Diagnostics and status reporter for Millennium helper scripts
set -euo pipefail

# Text color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
  cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  (None)        Run read-only diagnostics report (default)
  doctor        Detect and automatically repair partial or broken installations

Options:
  -f, --fix     Alias for the 'doctor' command
  -d, --dry-run Perform a dry-run (simulates doctor repairs without modifying anything)
  -h, --help    Show this help message
EOF
}

COMMAND=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    doctor|--fix|-f)
      COMMAND="doctor"
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
      echo -e "${RED}Unknown option: $1${NC}" >&2
      show_help
      exit 1
      ;;
  esac
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}=== DRY RUN MODE: No changes will be made ===${NC}"
fi

execute() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would run:${NC} $*"
  else
    "$@"
  fi
}

# --- State Variables for Diagnostics ---
STEAM_RUNNING=false
BINARIES_OK=true
HOOKS_OK=true
FLATPAK_OK=true
SUDOERS_OK=true
TIMER_ACTIVE=true
LINGER_OK=true
SCRIPTS_UP_TO_DATE=true

out_of_date_scripts=()
TMP_SCRIPTS=""

UTILITIES=(
  "millennium-repair:scripts/millennium-repair.sh"
  "millennium-upgrade-beta:scripts/millennium-upgrade-beta.sh"
  "millennium-upgrade-stable:scripts/millennium-upgrade-stable.sh"
  "millennium-schedule:scripts/millennium-schedule.sh"
  "millennium-purge:scripts/millennium-purge.sh"
  "millennium-diag:scripts/millennium-diag.sh"
)

RUNNING_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$RUNNING_USER" | cut -d: -f6)"
USER_CONFIG_DIR=""
if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
  user_xdg=$(runuser -l "$RUNNING_USER" -c 'echo "${XDG_CONFIG_HOME:-}"' 2>/dev/null || true)
  if [[ -n "$user_xdg" ]]; then
    USER_CONFIG_DIR="${user_xdg}/systemd/user"
  fi
fi
if [[ -z "$USER_CONFIG_DIR" ]]; then
  USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$USER_HOME/.config}/systemd/user"
fi

sysctl_user() {
  if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
    runuser -l "$RUNNING_USER" -c "systemctl --user $*"
  else
    systemctl --user "$@"
  fi
}

# Find configured update channel
UPDATE_CHANNEL="stable"
if [[ -f "/usr/lib/millennium/version.txt" ]]; then
  version_str=$(cat "/usr/lib/millennium/version.txt")
  if [[ "$version_str" == *"beta"* ]]; then
    UPDATE_CHANNEL="beta"
  fi
else
  # Fall back to checking systemd user service file if it exists
  SERVICE_PATH="${USER_CONFIG_DIR}/millennium-update.service"
  if [[ -f "$SERVICE_PATH" ]] && grep -q "upgrade-beta" "$SERVICE_PATH" 2>/dev/null; then
    UPDATE_CHANNEL="beta"
  fi
fi

echo -e "${BLUE}=== Millennium Diagnostics Report ===${NC}\n"

# 1. Check Steam Status
echo -n "Steam Client: "
if pgrep -x steam >/dev/null 2>&1; then
  STEAM_RUNNING=true
  echo -e "${GREEN}Running (PID: $(pgrep -x steam | head -n 1))${NC}"
else
  echo -e "${YELLOW}Not Running${NC}"
fi

# 2. Check Installed Millennium version & integrity
echo -n "Millennium Binary Version: "
if [[ -f "/usr/lib/millennium/version.txt" ]]; then
  # Verify .so files and integrity check
  if [[ ! -f "/usr/lib/millennium/libmillennium_bootstrap_x86.so" || ! -f "/usr/lib/millennium/libmillennium_bootstrap_hhx64.so" ]]; then
    BINARIES_OK=false
    echo -e "${RED}Corrupted (shared libraries are missing)${NC}"
  elif [[ ! -f "/usr/lib/millennium/checksums.txt" ]]; then
    BINARIES_OK=false
    echo -e "${RED}Corrupted (missing integrity manifest /usr/lib/millennium/checksums.txt)${NC}"
  elif ! (cd /usr/lib/millennium && sha256sum -c checksums.txt &>/dev/null); then
    BINARIES_OK=false
    echo -e "${RED}Corrupted (cryptographic checksum verification failed!)${NC}"
  else
    echo -e "${GREEN}v$(cat /usr/lib/millennium/version.txt) (${UPDATE_CHANNEL} channel) - Verified Healthy${NC}"
  fi
else
  BINARIES_OK=false
  echo -e "${RED}Not Installed (missing /usr/lib/millennium/version.txt)${NC}"
fi

# 3. Check Bootstrap Hook Status for Current User
echo -e "\nBootstrap Hooks (for user ${RUNNING_USER}):"
found_steam=false
broken_hooks=()
missing_hooks=()

for steam_dir in "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root" "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
  [[ -d "$steam_dir" ]] || continue
  found_steam=true
  
  # Determine environment type
  type_env="Native"
  if [[ "$steam_dir" == *"com.valvesoftware.Steam"* ]]; then
    type_env="Flatpak"
  fi
  
  echo -e "  Steam path [${type_env}]: ${steam_dir}"
  
  for arch in "ubuntu12_32:x86" "ubuntu12_64:hhx64"; do
    folder="${arch%%:*}"
    lib_name="${arch#*:}"
    hook_file="${steam_dir}/${folder}/libXtst.so.6"
    
    echo -n "    - ${folder} hook: "
    if [[ -L "$hook_file" ]]; then
      target=$(readlink "$hook_file")
      if [[ "$target" == *"/usr/lib/millennium/libmillennium_bootstrap_${lib_name}.so"* ]]; then
        if [[ -f "$target" ]]; then
          echo -e "${GREEN}Active and Verified${NC}"
        else
          HOOKS_OK=false
          broken_hooks+=("${steam_dir}:${folder}:${lib_name}")
          echo -e "${RED}Broken Symlink${NC} (target does not exist)"
        fi
      else
        echo -e "${YELLOW}Active, but points to custom library:${NC} ${target}"
      fi
    elif [[ -f "$hook_file" ]]; then
      echo -e "${YELLOW}Replaced by a real file (non-symlink)${NC}"
    else
      HOOKS_OK=false
      missing_hooks+=("${steam_dir}:${folder}:${lib_name}")
      echo -e "${RED}Inactive (missing symlink)${NC}"
    fi
  done

  # Flatpak specific checks
  if [[ "$type_env" == "Flatpak" ]]; then
    echo -n "    - Flatpak Sandbox Override: "
    flatpak_user_override="${USER_HOME}/.local/share/flatpak/overrides/com.valvesoftware.Steam"
    flatpak_sys_override="/var/lib/flatpak/overrides/com.valvesoftware.Steam"
    has_override=false
    
    for override_file in "$flatpak_user_override" "$flatpak_sys_override"; do
      if [[ -f "$override_file" ]] && grep -q "/usr/lib/millennium" "$override_file" 2>/dev/null; then
        has_override=true
        break
      fi
    done
    
    if [[ "$has_override" == true ]]; then
      echo -e "${GREEN}Configured (/usr/lib/millennium is visible inside container)${NC}"
    else
      FLATPAK_OK=false
      echo -e "${RED}Missing!${NC}"
    fi
  fi
done

if [[ "$found_steam" == false ]]; then
  echo -e "  ${RED}No Steam directories detected for the current user.${NC}"
fi

# 4. Check Sudoers Authorization
echo -n "Sudoers Passwordless Update Authorization: "
check_cmd="sudo -n -l"
if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
  check_cmd="sudo -U $RUNNING_USER -n -l"
fi

if eval "$check_cmd" 2>/dev/null | grep -qE "NOPASSWD.*(millennium-upgrade-stable|ALL)"; then
  echo -e "${GREEN}Active & Verified${NC}"
else
  SUDOERS_OK=false
  echo -e "${RED}Not Configured / Unauthorized${NC}"
fi

# 5. Check Systemd Auto-Update Timer
echo -n "Systemd Auto-Update Timer: "
TIMER_PATH="${USER_CONFIG_DIR}/millennium-update.timer"
if [[ -f "$TIMER_PATH" ]] && sysctl_user is-enabled millennium-update.timer &>/dev/null; then
  timer_state=$(sysctl_user is-active millennium-update.timer || echo "inactive")
  if [[ "$timer_state" == "active" ]]; then
    echo -e "${GREEN}Enabled and Active${NC}"
    timer_trigger=$(sysctl_user list-timers millennium-update.timer --no-legend | awk '{print $1, $2, $3}')
    echo "  Next Run: ${timer_trigger}"
  else
    TIMER_ACTIVE=false
    echo -e "${YELLOW}Enabled but Inactive (timer is sleeping)${NC}"
  fi
else
  TIMER_ACTIVE=false
  echo -e "${RED}Disabled / Not Scheduled${NC}"
fi

# 6. Check Systemd User Lingering status
echo -n "Systemd User Lingering: "
if [[ -f "/var/lib/systemd/linger/${RUNNING_USER}" ]]; then
  echo -e "${GREEN}Enabled${NC}"
else
  LINGER_OK=false
  echo -e "${YELLOW}Disabled (Updates will only trigger when user is logged in)${NC}"
fi

# 7. Check for Helper Script Updates
echo -e "\nHelper Scripts Update Status:"
# Check internet connectivity
ONLINE=false
if curl -sIk "https://github.com" &>/dev/null; then
  ONLINE=true
fi

if [[ "$ONLINE" == "true" ]]; then
  TMP_SCRIPTS=$(mktemp -d)
  trap 'rm -rf "${TMP_SCRIPTS:-}"' EXIT INT TERM
  
  # Fetch latest commit SHA to bypass raw.githubusercontent.com caching delays
  LATEST_SHA="main"
  if feed_data=$(curl -sL --retry 3 --retry-delay 2 "https://github.com/bolens/millenium-helpers/commits/main.atom" 2>/dev/null); then
    parsed_sha=$(echo "$feed_data" | grep -o 'Commit/[0-9a-f]\{40\}' | head -n 1 | cut -d/ -f2)
    if [[ -n "$parsed_sha" ]]; then
      LATEST_SHA="$parsed_sha"
    fi
  fi

  for item in "${UTILITIES[@]}"; do
    local_cmd="${item%%:*}"
    remote_rel="${item#*:}"
    local_path="/usr/local/bin/${local_cmd}"
    
    if [[ -f "$local_path" ]]; then
      remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${LATEST_SHA}/${remote_rel}"
      tmp_dest="${TMP_SCRIPTS}/${local_cmd}"
      
      if curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" &>/dev/null; then
        local_sha=$(sha256sum "$local_path" | awk '{print $1}')
        remote_sha=$(sha256sum "$tmp_dest" | awk '{print $1}')
        
        if [[ "$local_sha" != "$remote_sha" ]]; then
          SCRIPTS_UP_TO_DATE=false
          out_of_date_scripts+=("$local_cmd")
          echo -e "  - ${local_cmd}: ${RED}Out of date${NC}"
        else
          echo -e "  - ${local_cmd}: ${GREEN}Up to date${NC}"
        fi
      else
        echo -e "  - ${local_cmd}: ${YELLOW}Unable to check (HTTP download failed)${NC}"
      fi
    else
      echo -e "  - ${local_cmd}: ${RED}Not Installed in /usr/local/bin${NC}"
      SCRIPTS_UP_TO_DATE=false
      remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${LATEST_SHA}/${remote_rel}"
      tmp_dest="${TMP_SCRIPTS}/${local_cmd}"
      if curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" &>/dev/null; then
        out_of_date_scripts+=("$local_cmd")
      fi
    fi
  done
else
  echo -e "  ${YELLOW}System is offline. Skipping update checks for helper scripts.${NC}"
fi


# --- Doctor / Auto-Repair Execution ---
if [[ "$COMMAND" == "doctor" ]]; then
  echo -e "\n${BLUE}=== Running Millennium Doctor (Automatic Repairs) ===${NC}"
  
  # Check if anything needs fixing
  if [[ "$BINARIES_OK" == true && "$HOOKS_OK" == true && "$FLATPAK_OK" == true && "$SUDOERS_OK" == true && "$TIMER_ACTIVE" == true && "$LINGER_OK" == true && "$SCRIPTS_UP_TO_DATE" == true ]]; then
    echo -e "${GREEN}No issues detected. Your Millennium installation is healthy!${NC}"
    exit 0
  fi

  # Require Steam closed for any updates/repairs (only if binary or hook modifications are pending)
  if [[ "$STEAM_RUNNING" == true ]] && [[ "$BINARIES_OK" == false || "$HOOKS_OK" == false ]]; then
    echo -e "${RED}Error: Steam is currently running. Please close Steam completely before applying repairs to hooks or binaries.${NC}" >&2
    exit 1
  fi

  # Issue 1: Out of date helper scripts (do this first so repairs run on new code)
  if [[ "$SCRIPTS_UP_TO_DATE" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Updating helper scripts...${NC}"
    if [[ "$(id -u)" -ne 0 ]]; then
      echo -e "${RED}Error: Root privileges are required to update scripts in /usr/local/bin.${NC}" >&2
      echo -e "Please re-run the doctor with sudo: ${YELLOW}sudo millennium-diag doctor${NC}" >&2
    else
      for cmd_name in "${out_of_date_scripts[@]:-}"; do
        [[ -n "$cmd_name" ]] || continue
        tmp_src="${TMP_SCRIPTS}/${cmd_name}"
        dest_path="/usr/local/bin/${cmd_name}"
        if [[ -f "$tmp_src" ]]; then
          echo "Updating script: ${dest_path}"
          execute install -m755 "$tmp_src" "$dest_path"
          execute chown root:root "$dest_path"
        fi
      done
      echo -e "${GREEN}Helper scripts successfully updated!${NC}"
    fi
  fi

  # Issue 2: Missing or corrupted binaries
  if [[ "$BINARIES_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Repairing Millennium binaries...${NC}"
    echo -e "Invoking updater on the '${UPDATE_CHANNEL}' channel with force reinstall:"
    execute sudo "/usr/local/bin/millennium-upgrade-${UPDATE_CHANNEL}" --force
  fi

  # Issue 3: Missing or broken hooks
  if [[ "$HOOKS_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Repairing bootstrap hooks for Steam...${NC}"
    
    # Process broken symlinks
    for item in "${broken_hooks[@]:-}"; do
      [[ -n "$item" ]] || continue
      sdir="${item%%:*}"
      folder_arch="${item#*:}"
      folder="${folder_arch%%:*}"
      arch="${folder_arch#*:}"
      hook="${sdir}/${folder}/libXtst.so.6"
      
      echo "Fixing broken hook: $hook"
      execute rm -f "$hook"
      execute ln -sf "/usr/lib/millennium/libmillennium_bootstrap_${arch}.so" "$hook"
    done

    # Process missing symlinks
    for item in "${missing_hooks[@]:-}"; do
      [[ -n "$item" ]] || continue
      sdir="${item%%:*}"
      folder_arch="${item#*:}"
      folder="${folder_arch%%:*}"
      arch="${folder_arch#*:}"
      hook="${sdir}/${folder}/libXtst.so.6"
      
      echo "Installing missing hook: $hook"
      execute mkdir -p "${sdir}/${folder}"
      execute ln -sf "/usr/lib/millennium/libmillennium_bootstrap_${arch}.so" "$hook"
    done
  fi

  # Issue 4: Missing Flatpak sandbox override
  if [[ "$FLATPAK_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Granting Flatpak Steam permission to access Millennium directory...${NC}"
    execute flatpak override --user --filesystem=/usr/lib/millennium com.valvesoftware.Steam
  fi

  # Issue 5: Missing or invalid Sudoers drop-in
  if [[ "$SUDOERS_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Sudoers drop-in configuration is missing or unauthorized.${NC}"
    echo -e "You must re-run the installer to set up the secure drop-in rules:"
    echo -e "  ${YELLOW}sudo ./install.sh${NC} (from your cloned repository)"
  fi

  # Issue 6: Stopped systemd auto-update timer
  if [[ "$TIMER_ACTIVE" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Enabling and starting daily systemd user timer...${NC}"
    # Re-enable the timer using the configured channel
    if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
      execute runuser -l "$RUNNING_USER" -c "/usr/local/bin/millennium-schedule enable $UPDATE_CHANNEL"
    else
      execute /usr/local/bin/millennium-schedule enable "$UPDATE_CHANNEL"
    fi
  fi

  # Issue 7: Disabled systemd user lingering
  if [[ "$LINGER_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Enabling systemd user lingering to run updates in the background...${NC}"
    execute loginctl enable-linger "${RUNNING_USER}"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "\n${GREEN}Doctor dry-run simulation finished successfully!${NC}"
  else
    echo -e "\n${GREEN}Doctor repairs applied successfully! Re-run diagnostics to verify.${NC}"
  fi
fi
