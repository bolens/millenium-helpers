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
  -s, --share   Upload diagnostic report to a pastebin and return a short link
  -h, --help    Show this help message
EOF
}

ORIGINAL_ARGS=("$@")
COMMAND=""
DRY_RUN=false
FOLLOW_LOGS=false
FORCE_REPAIR=false
OUTPUT_JSON=false
SHARE_REPORT=false

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
    -s|--share)
      SHARE_REPORT=true
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

if [[ "$SHARE_REPORT" == "true" ]]; then
  echo "Generating and uploading diagnostic report..."
  
  clean_args=()
  for arg in "${ORIGINAL_ARGS[@]}"; do
    if [[ "$arg" != "-s" && "$arg" != "--share" ]]; then
      clean_args+=("$arg")
    fi
  done
  
  report_file=$(mktemp)
  trap 'rm -f "$report_file"' EXIT INT TERM
  
  # Run the diagnostic script itself with cleaned arguments
  bash "$0" "${clean_args[@]}" > "$report_file" 2>&1 || true
  
  # Sanitize user home and user name
  user_name="${SUDO_USER:-$(id -un)}"
  user_home="$(getent passwd "$user_name" | cut -d: -f6 || echo "")"
  if [[ -z "$user_home" ]]; then
    user_home="$HOME"
  fi
  
  # Replace home path and username to prevent info leakage
  sed -i "s|$user_home|~|g; s|$user_name|user|g" "$report_file"

  # Redact any GitHub Personal Access Tokens (PATs) and configuration tokens
  sed -i -E "s/ghp_[A-Za-z0-9_]+/\[REDACTED\]/g" "$report_file"
  sed -i -E "s/github_pat_[A-Za-z0-9_]+/\[REDACTED\]/g" "$report_file"

  user_config_dir="${XDG_CONFIG_HOME:-$user_home/.config}/millennium-helpers"
  loaded_token=""
  if [[ -f "${user_config_dir}/config.json" ]]; then
    loaded_token=$(python3 -c "
import json
try:
    with open('${user_config_dir}/config.json') as f:
        print(json.load(f).get('github_token', ''))
except Exception:
    pass
" 2>/dev/null)
  fi
  if [[ -n "$loaded_token" && ${#loaded_token} -ge 4 ]]; then
    sed -i "s|$loaded_token|\[REDACTED\]|g" "$report_file"
  fi
  if [[ -n "${GITHUB_TOKEN:-}" && ${#GITHUB_TOKEN} -ge 4 ]]; then
    sed -i "s|$GITHUB_TOKEN|\[REDACTED\]|g" "$report_file"
  fi
  
  # Upload using curl
  upload_url=$(curl -fsSL --data-binary @"$report_file" https://paste.rs || true)
  
  if [[ -n "$upload_url" && "$upload_url" == *"http"* ]]; then
    echo -e "${GREEN}Diagnostic report successfully shared!${NC}"
    echo -e "URL: ${BLUE}${upload_url}${NC}"
  else
    echo -e "${RED}Error: Failed to upload diagnostic report to paste.rs.${NC}" >&2
    exit 1
  fi
  exit 0
fi

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
CLEAN_OF_OBSOLETE=true
obsolete_files_found=()

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
  "millennium-upgrade:scripts/millennium-upgrade.sh"
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
  if [[ -f "$SERVICE_PATH" ]] && grep -qE "(--channel[[:space:]]+beta|--beta)" "$SERVICE_PATH" 2>/dev/null; then
    UPDATE_CHANNEL="beta"
  fi
fi

if [[ "$OUTPUT_JSON" == "true" ]]; then
  exec 3>&1
  exec 1>/dev/null
fi

print_diag_item() {
  local status="$1"
  local label="$2"
  local value="$3"
  
  if [[ "$status" == "ok" ]]; then
    printf "  [${GREEN}✔${NC}] %-45s : %b\n" "$label" "$value"
  elif [[ "$status" == "warn" ]]; then
    printf "  [${YELLOW}!${NC}] %-45s : %b\n" "$label" "$value"
  else
    printf "  [${RED}✘${NC}] %-45s : %b\n" "$label" "$value"
  fi
}

# --- Diagnostics Functions ---

check_steam_status() {
  if pgrep -x steam >/dev/null 2>&1; then
    STEAM_RUNNING=true
    print_diag_item "ok" "Steam Client" "Running (PID: $(pgrep -x steam | head -n 1))"
  else
    print_diag_item "warn" "Steam Client" "Not Running"
  fi
}

check_binaries_integrity() {
  if [[ -f "/usr/lib/millennium/version.txt" ]]; then
    if [[ ! -f "/usr/lib/millennium/libmillennium_bootstrap_x86.so" || \
          ! -f "/usr/lib/millennium/libmillennium_bootstrap_hhx64.so" || \
          ! -f "/usr/lib/millennium/libmillennium_x86.so" || \
          ! -f "/usr/lib/millennium/libmillennium_hhx64.so" || \
          ! -f "/usr/lib/millennium/libmillennium_pvs64" ]]; then
      BINARIES_OK=false
      print_diag_item "error" "Millennium Binary Version" "Corrupted (core libraries or wrapper binaries are missing)"
    elif [[ ! -f "/usr/lib/millennium/checksums.txt" ]]; then
      BINARIES_OK=false
      print_diag_item "error" "Millennium Binary Version" "Corrupted (missing integrity manifest /usr/lib/millennium/checksums.txt)"
    elif ! (cd /usr/lib/millennium && sha256sum -c checksums.txt &>/dev/null); then
      BINARIES_OK=false
      print_diag_item "error" "Millennium Binary Version" "Corrupted (cryptographic checksum verification failed!)"
    else
      print_diag_item "ok" "Millennium Binary Version" "v$(cat /usr/lib/millennium/version.txt) (${UPDATE_CHANNEL} channel) - Verified Healthy"
    fi
  else
    BINARIES_OK=false
    print_diag_item "error" "Millennium Binary Version" "Not Installed (missing /usr/lib/millennium/version.txt)"
  fi
}

check_bootstrap_hooks() {
  echo -e "\nBootstrap Hooks (for user ${RUNNING_USER}):"
  local found_steam=false
  broken_hooks=()
  missing_hooks=()

  for steam_dir in "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root" "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [[ -d "$steam_dir" ]] || continue
    found_steam=true
    
    # Determine environment type
    local type_env="Native"
    if [[ "$steam_dir" == *"com.valvesoftware.Steam"* ]]; then
      type_env="Flatpak"
    fi
    
    echo -e "  Steam path [${type_env}]: ${steam_dir}"
    
    for arch in "ubuntu12_32:x86" "ubuntu12_64:hhx64"; do
      local folder="${arch%%:*}"
      local lib_name="${arch#*:}"
      local hook_file="${steam_dir}/${folder}/libXtst.so.6"
      
      if [[ -L "$hook_file" ]]; then
        local target
        target=$(readlink "$hook_file")
        if [[ "$target" == *"/usr/lib/millennium/libmillennium_bootstrap_${lib_name}.so"* ]]; then
          if [[ -f "$target" ]]; then
            print_diag_item "ok" "    - Hook (${folder})" "Active and Verified"
          else
            HOOKS_OK=false
            broken_hooks+=("${steam_dir}:${folder}:${lib_name}")
            print_diag_item "error" "    - Hook (${folder})" "Broken Symlink (target does not exist)"
          fi
        else
          print_diag_item "warn" "    - Hook (${folder})" "Active, but points to custom library: ${target}"
        fi
      elif [[ -f "$hook_file" ]]; then
        print_diag_item "warn" "    - Hook (${folder})" "Replaced by a real file (non-symlink)"
      else
        HOOKS_OK=false
        missing_hooks+=("${steam_dir}:${folder}:${lib_name}")
        print_diag_item "error" "    - Hook (${folder})" "Inactive (missing symlink)"
      fi
    done

    # Flatpak specific checks
    if [[ "$type_env" == "Flatpak" ]]; then
      local flatpak_user_override="${USER_HOME}/.local/share/flatpak/overrides/com.valvesoftware.Steam"
      local flatpak_sys_override="/var/lib/flatpak/overrides/com.valvesoftware.Steam"
      local has_override=false
      
      for override_file in "$flatpak_user_override" "$flatpak_sys_override"; do
        if [[ -f "$override_file" ]] && grep -q "/usr/lib/millennium" "$override_file" 2>/dev/null; then
          has_override=true
          break
        fi
      done
      
      if [[ "$has_override" == true ]]; then
        print_diag_item "ok" "    - Flatpak Sandbox Override" "Configured (/usr/lib/millennium is visible inside container)"
      else
        FLATPAK_OK=false
        print_diag_item "error" "    - Flatpak Sandbox Override" "Missing!"
      fi
    fi
  done

  if [[ "$found_steam" == false ]]; then
    echo -e "  ${RED}No Steam directories detected for the current user.${NC}"
  fi
}

check_directory_permissions() {
  echo -e "\nMillennium Config & Theme Directory Permissions:"
  # A. Millennium User Config Directory
  local millennium_user_config=""
  if [[ -n "$user_xdg" ]]; then
    millennium_user_config="${user_xdg}/millennium"
  else
    millennium_user_config="${USER_HOME}/.config/millennium"
  fi

  if [[ -d "$millennium_user_config" ]]; then
    local config_owner
    config_owner=$(stat -c '%U' "$millennium_user_config" 2>/dev/null || echo "unknown")
    if [[ ! -w "$millennium_user_config" ]]; then
      PERMISSIONS_OK=false
      unwritable_dirs+=("$millennium_user_config")
      print_diag_item "error" "  - Config Directory (${millennium_user_config})" "Not Writable (Owned by: ${config_owner})"
    else
      print_diag_item "ok" "  - Config Directory (${millennium_user_config})" "Writable (Owned by: ${config_owner})"
    fi
  else
    print_diag_item "ok" "  - Config Directory (${millennium_user_config})" "Not Created Yet (will be created automatically by Millennium)"
  fi

  # B. Steam Skins/Themes directories
  for steam_dir in "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root" "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [[ -d "$steam_dir" ]] || continue
    local skins_dir="${steam_dir}/steamui/skins"
    local type_env="Native"
    if [[ "$steam_dir" == *"com.valvesoftware.Steam"* ]]; then
      type_env="Flatpak"
    fi
    
    if [[ -d "$skins_dir" ]]; then
      local skins_owner
      skins_owner=$(stat -c '%U' "$skins_dir" 2>/dev/null || echo "unknown")
      if [[ ! -w "$skins_dir" ]]; then
        PERMISSIONS_OK=false
        unwritable_dirs+=("$skins_dir")
        print_diag_item "error" "  - Skins Directory [${type_env}] (${skins_dir})" "Not Writable (Owned by: ${skins_owner})"
      else
        print_diag_item "ok" "  - Skins Directory [${type_env}] (${skins_dir})" "Writable (Owned by: ${skins_owner})"
      fi
    else
      # Skins directory doesn't exist, check parent
      local parent_dir
      parent_dir=$(dirname "$skins_dir")
      if [[ -d "$parent_dir" ]]; then
        local parent_owner
        parent_owner=$(stat -c '%U' "$parent_dir" 2>/dev/null || echo "unknown")
        if [[ ! -w "$parent_dir" ]]; then
          PERMISSIONS_OK=false
          unwritable_dirs+=("$parent_dir")
          print_diag_item "error" "  - Skins Parent [${type_env}] (${parent_dir})" "Parent Not Writable (Owned by: ${parent_owner})"
        else
          print_diag_item "warn" "  - Skins Directory [${type_env}] (${skins_dir})" "Missing (parent is writable, will be created automatically)"
          SKINS_DIR_OK=false
          missing_skins_dirs+=("$skins_dir")
        fi
      else
        print_diag_item "error" "  - Skins Directory [${type_env}] (${skins_dir})" "Steam Directory Missing"
      fi
    fi
  done
  echo ""
}

check_sudoers_authorization() {
  local check_cmd="sudo -n -l"
  if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
    check_cmd="sudo -U $RUNNING_USER -n -l"
  fi

  if eval "$check_cmd" 2>/dev/null | grep -qE "NOPASSWD.*(millennium-upgrade|ALL)"; then
    print_diag_item "ok" "Sudoers Passwordless Update Authorization" "Active & Verified"
  else
    SUDOERS_OK=false
    print_diag_item "error" "Sudoers Passwordless Update Authorization" "Not Configured / Unauthorized"
  fi
}

check_scheduler_status() {
  if [[ "$SYSTEMD_BOOTED" == "true" ]]; then
    local timer_path="${USER_CONFIG_DIR}/millennium-update.timer"
    if [[ -f "$timer_path" ]] && sysctl_user is-enabled millennium-update.timer &>/dev/null; then
      local timer_state
      timer_state=$(sysctl_user is-active millennium-update.timer || echo "inactive")
      if [[ "$timer_state" == "active" ]]; then
        local timer_trigger
        timer_trigger=$(sysctl_user list-timers millennium-update.timer --no-legend | awk '{print $1, $2, $3}')
        print_diag_item "ok" "Systemd Auto-Update Timer" "Enabled and Active (Next Run: ${timer_trigger})"
      else
        TIMER_ACTIVE=false
        print_diag_item "warn" "Systemd Auto-Update Timer" "Enabled but Inactive (timer is sleeping)"
      fi
    else
      TIMER_ACTIVE=false
      print_diag_item "error" "Systemd Auto-Update Timer" "Disabled / Not Scheduled"
    fi

    # Check Systemd User Lingering status
    if [[ -f "/var/lib/systemd/linger/${RUNNING_USER}" ]]; then
      print_diag_item "ok" "Systemd User Lingering" "Enabled"
    else
      LINGER_OK=false
      print_diag_item "warn" "Systemd User Lingering" "Disabled (Updates will only trigger when user is logged in)"
    fi
  else
    if command -v crontab &>/dev/null; then
      if crontab -l 2>/dev/null | grep -q "millennium-schedule"; then
        print_diag_item "ok" "Cron Auto-Update Scheduler" "Enabled and Active (Crontab entry configured)"
      else
        TIMER_ACTIVE=false
        print_diag_item "error" "Cron Auto-Update Scheduler" "Disabled / Not Scheduled"
      fi
    else
      TIMER_ACTIVE=false
      print_diag_item "error" "Cron Auto-Update Scheduler" "Disabled (No 'crontab' utility found)"
    fi
  fi
}

check_helper_updates() {
  echo -e "\nHelper Scripts Update Status:"
  ONLINE=false
  if curl -sIk "https://github.com" &>/dev/null; then
    ONLINE=true
  fi

  if [[ "$ONLINE" == "true" ]]; then
    TMP_SCRIPTS=$(mktemp -d)
    trap 'rm -rf "${TMP_SCRIPTS:-}"' EXIT INT TERM
    
    local latest_sha="main"
    local api_data
    if api_data=$(curl -sL --retry 3 --retry-delay 2 "https://api.github.com/repos/bolens/millenium-helpers/commits/main" 2>/dev/null); then
      local parsed_sha
      parsed_sha=$(echo "$api_data" | grep -m 1 '"sha":' | cut -d'"' -f4 || true)
      if [[ "$parsed_sha" =~ ^[0-9a-f]{40}$ ]]; then
        latest_sha="$parsed_sha"
      fi
    fi

    for item in "${UTILITIES[@]}"; do
      local cmd_name="${item%%:*}"
      local remote_rel="${item#*:}"
      local local_path=""
      if [[ -f "/usr/bin/${cmd_name}" ]]; then
        local_path="/usr/bin/${cmd_name}"
      elif [[ -f "/usr/local/bin/${cmd_name}" ]]; then
        local_path="/usr/local/bin/${cmd_name}"
      fi
      
      local remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${latest_sha}/${remote_rel}"
      local tmp_dest="${TMP_SCRIPTS}/${cmd_name}"
      
      if [[ -n "$local_path" ]]; then
        if curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" &>/dev/null; then
          local local_sha
          local_sha=$(sha256sum "$local_path" | awk '{print $1}')
          local remote_sha
          remote_sha=$(sha256sum "$tmp_dest" | awk '{print $1}')
          
          if [[ "$local_sha" != "$remote_sha" ]]; then
            SCRIPTS_UP_TO_DATE=false
            out_of_date_scripts+=("$cmd_name")
            print_diag_item "error" "  - ${cmd_name}" "Out of date"
          else
            print_diag_item "ok" "  - ${cmd_name}" "Up to date"
          fi
        else
          print_diag_item "warn" "  - ${cmd_name}" "Unable to check (HTTP download failed)"
        fi
      else
        print_diag_item "error" "  - ${cmd_name}" "Not Installed"
        SCRIPTS_UP_TO_DATE=false
        if curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" &>/dev/null; then
          out_of_date_scripts+=("$cmd_name")
        fi
      fi
    done
  else
    echo -e "  ${YELLOW}System is offline. Skipping update checks for helper scripts.${NC}"
  fi
}

check_shell_completions() {
  echo -e "\nShell Autocompletions Status:"

  # Define paths and their corresponding remote repository locations
  declare -A COMPLETION_FILES=(
    ["/usr/share/bash-completion/completions/millennium-helpers"]="completions/bash/millennium-helpers"
    ["/usr/share/zsh/site-functions/_millennium-helpers"]="completions/zsh/_millennium-helpers"
    ["/usr/share/fish/vendor_completions.d/millennium-repair.fish"]="completions/fish/millennium-repair.fish"
    ["/usr/share/fish/vendor_completions.d/millennium-upgrade.fish"]="completions/fish/millennium-upgrade.fish"
    ["/usr/share/fish/vendor_completions.d/millennium-schedule.fish"]="completions/fish/millennium-schedule.fish"
    ["/usr/share/fish/vendor_completions.d/millennium-purge.fish"]="completions/fish/millennium-purge.fish"
    ["/usr/share/fish/vendor_completions.d/millennium-diag.fish"]="completions/fish/millennium-diag.fish"
    ["/usr/share/fish/vendor_completions.d/millennium-theme.fish"]="completions/fish/millennium-theme.fish"
    ["/usr/share/fish/vendor_completions.d/millennium-mcp.fish"]="completions/fish/millennium-mcp.fish"
  )

  local nu_dest=""
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
    "/usr/share/bash-completion/completions/millennium-upgrade:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-schedule:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-purge:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-diag:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-theme:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-mcp:millennium-helpers"
    
    "/usr/share/zsh/site-functions/_millennium-repair:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-upgrade:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-schedule:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-purge:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-diag:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-theme:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-mcp:_millennium-helpers"
  )

  missing_completions=()
  out_of_date_completions=()

  for local_path in "${!COMPLETION_FILES[@]}"; do
    local remote_rel="${COMPLETION_FILES[$local_path]}"
    local local_dir
    local_dir=$(dirname "$local_path")
    [[ -d "$local_dir" ]] || continue
    
    if [[ ! -f "$local_path" ]]; then
      COMPLETIONS_OK=false
      missing_completions+=("$local_path")
      print_diag_item "error" "  - $(basename "$local_path")" "Missing"
    elif [[ "${ONLINE:-false}" == "true" ]]; then
      local remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${latest_sha:-main}/${remote_rel}"
      local tmp_dest
      tmp_dest="${TMP_SCRIPTS}/comp_$(basename "$local_path")"
      
      if curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" &>/dev/null; then
        local local_sha
        local_sha=$(sha256sum "$local_path" | awk '{print $1}')
        local remote_sha
        remote_sha=$(sha256sum "$tmp_dest" | awk '{print $1}')
        if [[ "$local_sha" != "$remote_sha" ]]; then
          COMPLETIONS_OK=false
          out_of_date_completions+=("$local_path")
          print_diag_item "error" "  - $(basename "$local_path")" "Out of date"
        else
          print_diag_item "ok" "  - $(basename "$local_path")" "Up to date"
        fi
      else
        print_diag_item "warn" "  - $(basename "$local_path")" "Unable to check (HTTP download failed)"
      fi
    else
      print_diag_item "ok" "  - $(basename "$local_path")" "Present (offline, cannot verify version)"
    fi
  done

  broken_symlinks=()
  for symlink_item in "${COMPLETION_SYMLINKS[@]}"; do
    local symlink_path="${symlink_item%%:*}"
    local symlink_target="${symlink_item#*:}"
    local symlink_dir
    symlink_dir=$(dirname "$symlink_path")
    [[ -d "$symlink_dir" ]] || continue
    
    if [[ ! -L "$symlink_path" ]]; then
      COMPLETIONS_OK=false
      broken_symlinks+=("$symlink_path:$symlink_target")
      print_diag_item "error" "  - $(basename "$symlink_path") symlink" "Missing/Broken"
    else
      local target_resolved
      target_resolved=$(readlink "$symlink_path" || true)
      if [[ "$target_resolved" != "$symlink_target" ]]; then
        COMPLETIONS_OK=false
        broken_symlinks+=("$symlink_path:$symlink_target")
        print_diag_item "error" "  - $(basename "$symlink_path") symlink" "Incorrect target (${target_resolved})"
      fi
    fi
  done
}

check_obsolete_files() {
  echo -e "\nObsolete / Deprecated Legacy Files:"
  local obsolete_list=()
  if [[ -n "${DIAG_TEST_OBSOLETE_LIST:-}" ]]; then
    IFS=',' read -r -a obsolete_list <<< "$DIAG_TEST_OBSOLETE_LIST"
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
    )
  fi

  local found_any=false
  for f in "${obsolete_list[@]}"; do
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

run_diagnostics() {
  echo -e "${BLUE}=== Millennium Diagnostics Report ===${NC}\n"
  
  check_steam_status
  check_binaries_integrity
  check_bootstrap_hooks
  check_directory_permissions
  check_sudoers_authorization
  check_scheduler_status
  check_helper_updates
  check_shell_completions
  check_obsolete_files
}

# --- Execute Diagnostics Report ---
run_diagnostics

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
  "clean_of_obsolete": ${CLEAN_OF_OBSOLETE},
  "update_channel": "${UPDATE_CHANNEL}"
}
EOF
  exit 0
fi

# --- Doctor / Auto-Repair Execution ---
if [[ "$COMMAND" == "doctor" ]]; then
  echo -e "\n${BLUE}=== Running Millennium Doctor (Automatic Repairs) ===${NC}"
  
  # Check if anything needs fixing
  if [[ "$FORCE_REPAIR" != "true" ]]; then
    if [[ "$BINARIES_OK" == true && "$HOOKS_OK" == true && "$FLATPAK_OK" == true && "$SUDOERS_OK" == true && "$TIMER_ACTIVE" == true && "$LINGER_OK" == true && "$SCRIPTS_UP_TO_DATE" == true && "$PERMISSIONS_OK" == true && "$SKINS_DIR_OK" == true && "$COMPLETIONS_OK" == true && "$CLEAN_OF_OBSOLETE" == true ]]; then
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
  fi

  # Require Steam closed for any updates/repairs (only if binary or hook modifications are pending)
  relaunch_steam_after_doctor=false
  if [[ "$STEAM_RUNNING" == true ]] && [[ "$BINARIES_OK" == false || "$HOOKS_OK" == false ]]; then
    if is_game_running; then
      echo -e "${RED}Error: A Steam game is currently running. Doctor repairs cannot proceed while a game is active.${NC}" >&2
      exit 1
    fi
    
    echo -e "${YELLOW}Steam is currently running and must be closed to apply repairs to hooks/binaries.${NC}"

    if [[ "$DRY_RUN" == "false" ]]; then
      capture_steam_env "$RUNNING_USER"
      close_steam_gracefully "$RUNNING_USER"
    else
      echo -e "${YELLOW}[DRY RUN] Would capture Steam's environment and close it to apply repairs.${NC}"
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
    upgrade_cmd="millennium-upgrade"
    upgrade_path="/usr/local/bin/${upgrade_cmd}"
    if [[ -f "/usr/bin/${upgrade_cmd}" ]]; then
      upgrade_path="/usr/bin/${upgrade_cmd}"
    fi
    execute sudo "${upgrade_path}" --channel "${UPDATE_CHANNEL}" --force
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
      remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${latest_sha:-main}/${remote_rel}"
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

  # Issue 11: Cleanup of obsolete / deprecated files
  if [[ "$CLEAN_OF_OBSOLETE" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Cleaning up obsolete / deprecated legacy files...${NC}"
    for f in "${obsolete_files_found[@]:-}"; do
      [[ -n "$f" ]] || continue
      parent_dir=$(dirname "$f")
      if [[ -w "$parent_dir" ]]; then
        echo "Removing deprecated file: $f"
        execute rm -f "$f"
      else
        echo -e "${RED}Warning: Directory '${parent_dir}' is not writable. Skipping removal of ${f}.${NC}"
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

    if [[ "$DRY_RUN" == "true" ]]; then
      execute relaunch_steam "$RUNNING_USER"
    else
      relaunch_steam "$RUNNING_USER"
    fi
  fi
fi
