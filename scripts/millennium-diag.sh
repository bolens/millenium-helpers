#!/usr/bin/env bash
# Diagnostics and status reporter for Millennium helper scripts
set -euo pipefail

# Source shared helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH="${SCRIPT_DIR}/common.sh"
if [[ ! -f "$COMMON_SH" ]]; then
  COMMON_SH="/usr/local/lib/millennium-helpers/common.sh"
  if [[ -f "/usr/lib/millennium-helpers/common.sh" ]]; then
    COMMON_SH="/usr/lib/millennium-helpers/common.sh"
  fi
fi
if [[ -f "$COMMON_SH" ]]; then
  # shellcheck disable=SC1090
  source "$COMMON_SH"
else
  echo -e "${RED:-}Error: Shared helper library not found." >&2
  exit 1
fi

show_help() {
  cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  (None)        Run read-only diagnostics report (default)
  doctor        Detect and automatically repair partial or broken installations
  logs          Display recent Millennium and Steam WebHelper startup logs

Options:
  -f, --fix     Alias for the 'doctor' command
  --force       Force all doctor repairs even if system is healthy
  --json        Output diagnostics report in structured JSON format
  -l, --follow  Follow (tail -f) real-time log output
  -d, --dry-run Perform a dry-run (simulates doctor repairs without modifying anything)
  -h, --help    Show this help message
EOF
}

COMMAND=""
DRY_RUN=false
FOLLOW_LOGS=false
FORCE_REPAIR=false
OUTPUT_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    doctor|--fix|-f)
      COMMAND="doctor"
      shift
      ;;
    logs)
      COMMAND="logs"
      shift
      ;;
    --force)
      FORCE_REPAIR=true
      shift
      ;;
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    -l|--follow)
      FOLLOW_LOGS=true
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

# --- State Variables for Diagnostics ---
STEAM_RUNNING=false
BINARIES_OK=true
HOOKS_OK=true
FLATPAK_OK=true
SUDOERS_OK=true
TIMER_ACTIVE=true
LINGER_OK=true
SCRIPTS_UP_TO_DATE=true
PERMISSIONS_OK=true
SKINS_DIR_OK=true
COMPLETIONS_OK=true

SYSTEMD_BOOTED=false
if [[ -d /run/systemd/system ]]; then
  SYSTEMD_BOOTED=true
fi

out_of_date_scripts=()
unwritable_dirs=()
missing_skins_dirs=()
TMP_SCRIPTS=""

UTILITIES=(
  "millennium-repair:scripts/millennium-repair.sh"
  "millennium-upgrade-beta:scripts/millennium-upgrade-beta.sh"
  "millennium-upgrade-stable:scripts/millennium-upgrade-stable.sh"
  "millennium-schedule:scripts/millennium-schedule.sh"
  "millennium-purge:scripts/millennium-purge.sh"
  "millennium-diag:scripts/millennium-diag.sh"
  "millennium-theme:scripts/millennium-theme.sh"
  "millennium-mcp:scripts/millennium-mcp.py"
)

RUNNING_USER="${SUDO_USER:-$(id -un)}"
USER_HOME="$(getent passwd "$RUNNING_USER" | cut -d: -f6)"
USER_CONFIG_DIR=""
user_xdg=""
if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
  # shellcheck disable=SC2016
  user_xdg=$(runuser -l "$RUNNING_USER" -c 'echo "${XDG_CONFIG_HOME:-}"' 2>/dev/null || true)
else
  user_xdg="${XDG_CONFIG_HOME:-}"
fi

if [[ -n "$user_xdg" ]]; then
  USER_CONFIG_DIR="${user_xdg}/systemd/user"
else
  USER_CONFIG_DIR="${USER_HOME}/.config/systemd/user"
fi

# --- Logs Viewer Execution ---
if [[ "$COMMAND" == "logs" ]]; then
  state_dir="${XDG_STATE_HOME:-$USER_HOME/.local/state}/millennium-helpers"
  if [[ -f "${state_dir}/updater.log" ]]; then
    echo -e "${BLUE}=== Millennium Background Auto-Updater Logs ===${NC}"
    tail -n 50 "${state_dir}/updater.log"
    echo -e "\n"
  fi

  echo -e "${BLUE}=== Millennium & Steam WebHelper Logs ===${NC}"
  
  # Find latest log files
  log_files=()
  for steam_dir in "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root" "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [[ -d "$steam_dir/logs" ]] || continue
    if [[ -f "$steam_dir/logs/webhelper-linux.txt" ]]; then
      log_files+=("$steam_dir/logs/webhelper-linux.txt")
    fi
    if [[ -f "$steam_dir/logs/console-linux.txt" ]]; then
      log_files+=("$steam_dir/logs/console-linux.txt")
    fi
  done
  
  if [[ ${#log_files[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No Steam logs found on this system.${NC}" >&2
    exit 1
  fi
  
  # Pick the newest log file
  latest_log=""
  latest_mtime=0
  for f in "${log_files[@]}"; do
    mtime=$(stat -c '%Y' "$f" 2>/dev/null || echo 0)
    if (( mtime > latest_mtime )); then
      latest_mtime=$mtime
      latest_log=$f
    fi
  done
  
  if [[ -z "$latest_log" ]]; then
    echo -e "${RED}Error: Could not resolve the most recent log file.${NC}" >&2
    exit 1
  fi
  
  echo -e "${YELLOW}Reading log file: ${latest_log}${NC}\n"
  
  filter_regex="Millennium|BOOTSTRAP|update-check|plugin_loader|pressure-vessel|steamwebhelper"
  
  if [[ "$FOLLOW_LOGS" == "true" ]]; then
    echo "Tailing log file (Ctrl+C to exit)..."
    tail -n 100 -f "$latest_log" | grep --line-buffered -iE "$filter_regex"
  else
    # Output matching lines in the last 200 lines
    tail -n 200 "$latest_log" | grep -iE "$filter_regex" || echo "No recent Millennium-related log entries found."
  fi
  exit 0
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

if [[ "$OUTPUT_JSON" == "true" ]]; then
  exec 3>&1
  exec 1>/dev/null
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
  if [[ ! -f "/usr/lib/millennium/libmillennium_bootstrap_x86.so" || \
        ! -f "/usr/lib/millennium/libmillennium_bootstrap_hhx64.so" || \
        ! -f "/usr/lib/millennium/libmillennium_x86.so" || \
        ! -f "/usr/lib/millennium/libmillennium_hhx64.so" || \
        ! -f "/usr/lib/millennium/libmillennium_pvs64" ]]; then
    BINARIES_OK=false
    echo -e "${RED}Corrupted (core libraries or wrapper binaries are missing)${NC}"
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

# 3.5. Check Config & Theme Directories permissions
echo -e "\nMillennium Config & Theme Directory Permissions:"
# A. Millennium User Config Directory
millennium_user_config=""
if [[ -n "$user_xdg" ]]; then
  millennium_user_config="${user_xdg}/millennium"
else
  millennium_user_config="${USER_HOME}/.config/millennium"
fi

echo -n "  - Config Directory (${millennium_user_config}): "
if [[ -d "$millennium_user_config" ]]; then
  config_owner=$(stat -c '%U' "$millennium_user_config" 2>/dev/null || echo "unknown")
  if [[ ! -w "$millennium_user_config" ]]; then
    PERMISSIONS_OK=false
    unwritable_dirs+=("$millennium_user_config")
    echo -e "${RED}Not Writable${NC} (Owned by: ${config_owner})"
  else
    echo -e "${GREEN}Writable${NC} (Owned by: ${config_owner})"
  fi
else
  echo -e "${GREEN}Not Created Yet${NC} (will be created automatically by Millennium)"
fi

# B. Steam Skins/Themes directories
for steam_dir in "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root" "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
  [[ -d "$steam_dir" ]] || continue
  skins_dir="${steam_dir}/steamui/skins"
  type_env="Native"
  if [[ "$steam_dir" == *"com.valvesoftware.Steam"* ]]; then
    type_env="Flatpak"
  fi
  
  echo -n "  - Skins Directory [${type_env}] (${skins_dir}): "
  if [[ -d "$skins_dir" ]]; then
    skins_owner=$(stat -c '%U' "$skins_dir" 2>/dev/null || echo "unknown")
    if [[ ! -w "$skins_dir" ]]; then
      PERMISSIONS_OK=false
      unwritable_dirs+=("$skins_dir")
      echo -e "${RED}Not Writable${NC} (Owned by: ${skins_owner})"
    else
      echo -e "${GREEN}Writable${NC} (Owned by: ${skins_owner})"
    fi
  else
    # Skins directory doesn't exist, check parent
    parent_dir=$(dirname "$skins_dir")
    if [[ -d "$parent_dir" ]]; then
      parent_owner=$(stat -c '%U' "$parent_dir" 2>/dev/null || echo "unknown")
      if [[ ! -w "$parent_dir" ]]; then
        PERMISSIONS_OK=false
        unwritable_dirs+=("$parent_dir")
        echo -e "${RED}Parent Not Writable${NC} (Owned by: ${parent_owner})"
      else
        echo -e "${YELLOW}Missing (parent is writable, will be created automatically)${NC}"
        SKINS_DIR_OK=false
        missing_skins_dirs+=("$skins_dir")
      fi
    else
      echo -e "${RED}Steam Directory Missing${NC}"
    fi
  fi
done
echo ""

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

# 5. Check Update Scheduler Status
if [[ "$SYSTEMD_BOOTED" == "true" ]]; then
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
else
  echo -n "Cron Auto-Update Scheduler: "
  if command -v crontab &>/dev/null; then
    if crontab -l 2>/dev/null | grep -q "millennium-schedule"; then
      echo -e "${GREEN}Enabled and Active (Crontab entry configured)${NC}"
    else
      TIMER_ACTIVE=false
      echo -e "${RED}Disabled / Not Scheduled${NC}"
    fi
  else
    TIMER_ACTIVE=false
    echo -e "${RED}Disabled (No 'crontab' utility found)${NC}"
  fi
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
  
  LATEST_SHA="main"
  if api_data=$(curl -sL --retry 3 --retry-delay 2 "https://api.github.com/repos/bolens/millenium-helpers/commits/main" 2>/dev/null); then
    parsed_sha=$(echo "$api_data" | grep -m 1 '"sha":' | cut -d'"' -f4 || true)
    if [[ "$parsed_sha" =~ ^[0-9a-f]{40}$ ]]; then
      LATEST_SHA="$parsed_sha"
    fi
  fi

  for item in "${UTILITIES[@]}"; do
    local_cmd="${item%%:*}"
    remote_rel="${item#*:}"
    local_path=""
    if [[ -f "/usr/bin/${local_cmd}" ]]; then
      local_path="/usr/bin/${local_cmd}"
    elif [[ -f "/usr/local/bin/${local_cmd}" ]]; then
      local_path="/usr/local/bin/${local_cmd}"
    fi
    
    if [[ -n "$local_path" ]]; then
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
      echo -e "  - ${local_cmd}: ${RED}Not Installed${NC}"
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
# 8. Check Shell Completions Status
echo -e "\nShell Autocompletions Status:"

# Define paths and their corresponding remote repository locations
declare -A COMPLETION_FILES=(
  ["/usr/share/bash-completion/completions/millennium-helpers"]="completions/bash/millennium-helpers"
  ["/usr/share/zsh/site-functions/_millennium-helpers"]="completions/zsh/_millennium-helpers"
  ["/usr/share/fish/vendor_completions.d/millennium-repair.fish"]="completions/fish/millennium-repair.fish"
  ["/usr/share/fish/vendor_completions.d/millennium-upgrade-beta.fish"]="completions/fish/millennium-upgrade-beta.fish"
  ["/usr/share/fish/vendor_completions.d/millennium-upgrade-stable.fish"]="completions/fish/millennium-upgrade-stable.fish"
  ["/usr/share/fish/vendor_completions.d/millennium-schedule.fish"]="completions/fish/millennium-schedule.fish"
  ["/usr/share/fish/vendor_completions.d/millennium-purge.fish"]="completions/fish/millennium-purge.fish"
  ["/usr/share/fish/vendor_completions.d/millennium-diag.fish"]="completions/fish/millennium-diag.fish"
  ["/usr/share/fish/vendor_completions.d/millennium-theme.fish"]="completions/fish/millennium-theme.fish"
  ["/usr/share/fish/vendor_completions.d/millennium-mcp.fish"]="completions/fish/millennium-mcp.fish"
)

nu_dest=""
for base_dir in "/usr/share" "/usr/local/share"; do
  if [[ -d "${base_dir}/nushell/completions" ]]; then
    nu_dest="${base_dir}/nushell/completions/millennium-helpers.nu"
    break
  fi
done
if [[ -z "$nu_dest" ]]; then
  nu_dest="/usr/share/nushell/completions/millennium-helpers.nu"
fi
COMPLETION_FILES["$nu_dest"]="completions/nushell/millennium-helpers.nu"

declare -a COMPLETION_SYMLINKS=(
  "/usr/share/bash-completion/completions/millennium-repair:millennium-helpers"
  "/usr/share/bash-completion/completions/millennium-upgrade-beta:millennium-helpers"
  "/usr/share/bash-completion/completions/millennium-upgrade-stable:millennium-helpers"
  "/usr/share/bash-completion/completions/millennium-schedule:millennium-helpers"
  "/usr/share/bash-completion/completions/millennium-purge:millennium-helpers"
  "/usr/share/bash-completion/completions/millennium-diag:millennium-helpers"
  "/usr/share/bash-completion/completions/millennium-theme:millennium-helpers"
  "/usr/share/bash-completion/completions/millennium-mcp:millennium-helpers"
  
  "/usr/share/zsh/site-functions/_millennium-repair:_millennium-helpers"
  "/usr/share/zsh/site-functions/_millennium-upgrade-beta:_millennium-helpers"
  "/usr/share/zsh/site-functions/_millennium-upgrade-stable:_millennium-helpers"
  "/usr/share/zsh/site-functions/_millennium-schedule:_millennium-helpers"
  "/usr/share/zsh/site-functions/_millennium-purge:_millennium-helpers"
  "/usr/share/zsh/site-functions/_millennium-diag:_millennium-helpers"
  "/usr/share/zsh/site-functions/_millennium-theme:_millennium-helpers"
  "/usr/share/zsh/site-functions/_millennium-mcp:_millennium-helpers"
)

missing_completions=()
out_of_date_completions=()

for local_path in "${!COMPLETION_FILES[@]}"; do
  remote_rel="${COMPLETION_FILES[$local_path]}"
  
  local_dir=$(dirname "$local_path")
  [[ -d "$local_dir" ]] || continue
  
  if [[ ! -f "$local_path" ]]; then
    COMPLETIONS_OK=false
    missing_completions+=("$local_path")
    echo -e "  - $(basename "$local_path"): ${RED}Missing${NC}"
  elif [[ "${ONLINE:-false}" == "true" ]]; then
    remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${LATEST_SHA}/${remote_rel}"
    tmp_dest="${TMP_SCRIPTS}/comp_$(basename "$local_path")"
    
    if curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" &>/dev/null; then
      local_sha=$(sha256sum "$local_path" | awk '{print $1}')
      remote_sha=$(sha256sum "$tmp_dest" | awk '{print $1}')
      if [[ "$local_sha" != "$remote_sha" ]]; then
        COMPLETIONS_OK=false
        out_of_date_completions+=("$local_path")
        echo -e "  - $(basename "$local_path"): ${RED}Out of date${NC}"
      else
        echo -e "  - $(basename "$local_path"): ${GREEN}Up to date${NC}"
      fi
    else
      echo -e "  - $(basename "$local_path"): ${YELLOW}Unable to check (HTTP download failed)${NC}"
    fi
  else
    echo -e "  - $(basename "$local_path"): ${GREEN}Present (offline, cannot verify version)${NC}"
  fi
done

broken_symlinks=()
for symlink_item in "${COMPLETION_SYMLINKS[@]}"; do
  symlink_path="${symlink_item%%:*}"
  symlink_target="${symlink_item#*:}"
  
  symlink_dir=$(dirname "$symlink_path")
  [[ -d "$symlink_dir" ]] || continue
  
  if [[ ! -L "$symlink_path" ]]; then
    COMPLETIONS_OK=false
    broken_symlinks+=("$symlink_path:$symlink_target")
    echo -e "  - $(basename "$symlink_path") symlink: ${RED}Missing/Broken${NC}"
  else
    target_resolved=$(readlink "$symlink_path" || true)
    if [[ "$target_resolved" != "$symlink_target" ]]; then
      COMPLETIONS_OK=false
      broken_symlinks+=("$symlink_path:$symlink_target")
      echo -e "  - $(basename "$symlink_path") symlink: ${RED}Incorrect target (${target_resolved})${NC}"
    fi
  fi
done

# is_game_running is now sourced from common.sh

if [[ "$OUTPUT_JSON" == "true" ]]; then
  exec 1>&3
  exec 3>&-
  cat <<EOF
{
  "steam_running": ${STEAM_RUNNING},
  "binaries_ok": ${BINARIES_OK},
  "hooks_ok": ${HOOKS_OK},
  "flatpak_ok": ${FLATPAK_OK},
  "sudoers_ok": ${SUDOERS_OK},
  "timer_active": ${TIMER_ACTIVE},
  "linger_ok": ${LINGER_OK},
  "scripts_up_to_date": ${SCRIPTS_UP_TO_DATE},
  "permissions_ok": ${PERMISSIONS_OK},
  "skins_dir_ok": ${SKINS_DIR_OK},
  "completions_ok": ${COMPLETIONS_OK},
  "update_channel": "${UPDATE_CHANNEL}"
}
EOF
  exit 0
fi

# --- Doctor / Auto-Repair Execution ---
if [[ "$COMMAND" == "doctor" ]]; then
  echo -e "\n${BLUE}=== Running Millennium Doctor (Automatic Repairs) ===${NC}"
  
  # Check if anything needs fixing
  # Check if anything needs fixing
  if [[ "$FORCE_REPAIR" != "true" ]]; then
    if [[ "$BINARIES_OK" == true && "$HOOKS_OK" == true && "$FLATPAK_OK" == true && "$SUDOERS_OK" == true && "$TIMER_ACTIVE" == true && "$LINGER_OK" == true && "$SCRIPTS_UP_TO_DATE" == true && "$PERMISSIONS_OK" == true && "$SKINS_DIR_OK" == true && "$COMPLETIONS_OK" == true ]]; then
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
  fi

  # Require Steam closed for any updates/repairs (only if binary or hook modifications are pending)
  relaunch_steam_after_doctor=false
  if [[ "$STEAM_RUNNING" == true ]] && [[ "$BINARIES_OK" == false || "$HOOKS_OK" == false ]]; then
    if is_game_running; then
      echo -e "${RED}Error: A Steam game is currently running. Doctor repairs cannot proceed while a game is active.${NC}" >&2
      exit 1
    fi
    
    echo -e "${YELLOW}Steam is currently running and must be closed to apply repairs to hooks/binaries.${NC}"
    
    # Capture env and command line arguments
    capture_steam_env "$RUNNING_USER" "/tmp/millennium-relaunch-${RUNNING_USER}"
    
    # Close Steam gracefully
    if [[ "$DRY_RUN" == "false" ]]; then
      close_steam_gracefully "$RUNNING_USER"
    fi
    
    STEAM_RUNNING=false
    relaunch_steam_after_doctor=true
  fi

  # Issue 1: Out of date helper scripts (do this first so repairs run on new code)
  if [[ "$SCRIPTS_UP_TO_DATE" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Updating helper scripts...${NC}"
    if [[ "$(id -u)" -ne 0 ]]; then
      echo -e "${RED}Error: Root privileges are required to update helper scripts.${NC}" >&2
      echo -e "Please re-run the doctor with sudo: ${YELLOW}sudo $(basename "$0") doctor${NC}" >&2
    else
      for cmd_name in "${out_of_date_scripts[@]:-}"; do
        [[ -n "$cmd_name" ]] || continue
        tmp_src="${TMP_SCRIPTS}/${cmd_name}"
        dest_path="/usr/local/bin/${cmd_name}"
        if [[ -f "/usr/bin/${cmd_name}" ]]; then
          dest_path="/usr/bin/${cmd_name}"
        fi
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
    upgrade_cmd="millennium-upgrade-${UPDATE_CHANNEL}"
    upgrade_path="/usr/local/bin/${upgrade_cmd}"
    if [[ -f "/usr/bin/${upgrade_cmd}" ]]; then
      upgrade_path="/usr/bin/${upgrade_cmd}"
    fi
    execute sudo "${upgrade_path}" --force
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

  # Issue 6: Ensure daily update timer / cron job is configured and up to date
  sched_path=$(resolve_helper_path "millennium-schedule")
  if [[ "$SYSTEMD_BOOTED" == "true" ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Refreshing daily systemd user timer...${NC}"
    if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
      execute runuser -l "$RUNNING_USER" -c "${sched_path} enable $UPDATE_CHANNEL"
    else
      execute "${sched_path}" enable "$UPDATE_CHANNEL"
    fi
  else
    echo -e "\n${YELLOW}[DOCTOR] Refreshing daily cron update job...${NC}"
    if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
      execute runuser -l "$RUNNING_USER" -c "${sched_path} enable $UPDATE_CHANNEL --cron"
    else
      execute "${sched_path}" enable "$UPDATE_CHANNEL" --cron
    fi
  fi

  # Issue 7: Disabled systemd user lingering (Only on systemd booted)
  if [[ "$SYSTEMD_BOOTED" == "true" && "$LINGER_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Enabling systemd user lingering to run updates in the background...${NC}"
    execute loginctl enable-linger "${RUNNING_USER}"
  fi

  # Issue 8: Incorrect directory permissions or ownership
  if [[ "$PERMISSIONS_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Repairing directory permissions and ownership...${NC}"
    for dir in "${unwritable_dirs[@]:-}"; do
      [[ -n "$dir" ]] || continue
      echo "Correcting ownership and permissions for: ${dir}"
      if [[ "$(id -u)" -eq 0 ]]; then
        execute chown -R "${RUNNING_USER}:${RUNNING_USER}" "$dir"
        execute chmod -R u+rwX "$dir"
      else
        echo -e "${RED}Error: Root privileges are required to fix ownership of ${dir}.${NC}" >&2
        echo -e "Please re-run the doctor with sudo: ${YELLOW}sudo millennium-diag doctor${NC}" >&2
      fi
    done
  fi

  # Issue 9: Missing skins directories
  if [[ "${#missing_skins_dirs[@]}" -gt 0 ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Creating missing skins directories...${NC}"
    for dir in "${missing_skins_dirs[@]}"; do
      echo "Creating directory: ${dir}"
      if [[ "$DRY_RUN" == "false" ]]; then
        execute mkdir -p "$dir"
        if [[ "$(id -u)" -eq 0 ]]; then
          execute chown "${RUNNING_USER}:${RUNNING_USER}" "$dir"
        fi
        execute chmod 755 "$dir"
      fi
    done
  fi

  # Issue 10: Missing or out-of-date completions
  if [[ "$COMPLETIONS_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Repairing shell autocompletions...${NC}"
    
    # 1. Restore files
    for local_path in "${missing_completions[@]:-}" "${out_of_date_completions[@]:-}"; do
      [[ -n "$local_path" ]] || continue
      remote_rel="${COMPLETION_FILES[$local_path]}"
      remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${LATEST_SHA}/${remote_rel}"
      echo "Restoring completion file: $local_path"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "[DRY RUN] Would download $remote_url to $local_path"
      else
        execute curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$local_path"
        execute chmod 644 "$local_path"
      fi
    done
    
    # 2. Restore symlinks
    for symlink_item in "${broken_symlinks[@]:-}"; do
      [[ -n "$symlink_item" ]] || continue
      symlink_path="${symlink_item%%:*}"
      symlink_target="${symlink_item#*:}"
      echo "Restoring symlink: $symlink_path -> $symlink_target"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "[DRY RUN] Would link $symlink_path to $symlink_target"
      else
        execute rm -f "$symlink_path"
        execute ln -sf "$symlink_target" "$symlink_path"
      fi
    done
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "\n${GREEN}Doctor dry-run simulation finished successfully!${NC}"
  else
    echo -e "\n${GREEN}Doctor repairs applied successfully! Re-run diagnostics to verify.${NC}"
  fi

  if [[ "$relaunch_steam_after_doctor" == "true" ]]; then
    echo -e "\n${GREEN}Relaunching Steam...${NC}"
    
    # Source saved environment variables (sets DISPLAY, WAYLAND_DISPLAY, STEAM_ARGS, WAS_FLATPAK, etc.)
    # shellcheck disable=SC1090
    source "/tmp/millennium-relaunch-${RUNNING_USER}"
    rm -f "/tmp/millennium-relaunch-${RUNNING_USER}"

    if [[ "${WAS_FLATPAK:-false}" == "true" ]]; then
      execute runuser "$RUNNING_USER" -c "flatpak run com.valvesoftware.Steam ${STEAM_ARGS} >/dev/null 2>&1 &"
    else
      if command -v steam &>/dev/null; then
        execute runuser "$RUNNING_USER" -c "steam ${STEAM_ARGS} >/dev/null 2>&1 &"
      elif [[ -x "${USER_HOME}/.local/bin/steam" ]]; then
        execute runuser "$RUNNING_USER" -c "${USER_HOME}/.local/bin/steam ${STEAM_ARGS} >/dev/null 2>&1 &"
      fi
    fi
  fi
fi
