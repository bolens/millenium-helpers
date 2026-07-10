#!/usr/bin/env bash
# Diagnostics and status reporter for Millennium helper scripts
set -euo pipefail

# Source shared helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH=""
for _common_candidate in \
  "${SCRIPT_DIR}/common.sh" \
  "$(cd "${SCRIPT_DIR}/.." && pwd)/lib/millennium-helpers/common.sh" \
  "/usr/local/lib/millennium-helpers/common.sh" \
  "/usr/lib/millennium-helpers/common.sh"
do
  if [[ -f "$_common_candidate" ]]; then
    COMMON_SH="$_common_candidate"
    break
  fi
done
unset _common_candidate
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
  -y, --yes     Skip confirmation when doctor closes Steam
  -d, --dry-run Perform a dry-run (simulates doctor repairs without modifying anything)
  -q, --quiet   Suppress informational output
  -s, --share   Upload diagnostic report to a pastebin and return a short link
  -V, --version Show version information
  -h, --help    Show this help message
EOF
}

ORIGINAL_ARGS=("$@")
COMMAND=""
DRY_RUN=false
QUIET=false
ASSUME_YES=false
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
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -q|--quiet)
      export QUIET=true
      export MILLENNIUM_QUIET=1
      shift
      ;;
    -s|--share)
      SHARE_REPORT=true
      shift
      ;;
    -V|--version)
      print_helpers_version
      exit 0
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      if [[ "$1" != -* ]]; then
        echo -e "${RED}Unknown command: $1${NC}" >&2
        suggestion="$(suggest_closest "$1" doctor logs || true)"
        if [[ -n "$suggestion" ]]; then
          echo "Did you mean '${suggestion}'?" >&2
        fi
      else
        echo -e "${RED}Unknown option: $1${NC}" >&2
      fi
      echo "Try '$(basename "$0") --help' for usage." >&2
      exit 1
      ;;
  esac
done

if [[ "$SHARE_REPORT" == "true" ]]; then
  echo "Generating and uploading diagnostic report..."
  
  safe_sed_i() {
    local use_E=false
    if [[ "$1" == "-E" ]]; then
      use_E=true
      shift
    fi
    local pattern="$1"
    local file="$2"
    local temp_file
    temp_file=$(mktemp 2>/dev/null || mktemp -t tmp.XXXXXX)
    if [[ "$use_E" == "true" ]]; then
      sed -E "$pattern" "$file" > "$temp_file"
    else
      sed "$pattern" "$file" > "$temp_file"
    fi
    mv -f "$temp_file" "$file"
  }
  
  clean_args=()
  # Bash 3.2 (macOS): empty "${arr[@]}" is unbound under set -u.
  for arg in ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}; do
    if [[ "$arg" != "-s" && "$arg" != "--share" ]]; then
      clean_args+=("$arg")
    fi
  done
  
  report_file=$(mktemp 2>/dev/null || mktemp -t tmp.XXXXXX)
  trap 'rm -f "$report_file"' EXIT INT TERM
  
  # Run the diagnostic script itself with cleaned arguments.
  # Bash 3.2 (macOS) treats "${arr[@]}" as unbound under set -u when empty
  # (e.g. `millennium-diag --share` with no other flags).
  bash "$0" ${clean_args[@]+"${clean_args[@]}"} > "$report_file" 2>&1 || true
  
  # Sanitize user home and user name
  user_name="${SUDO_USER:-$(id -un)}"
  user_home="$(get_user_home "$user_name")"
  if [[ -z "$user_home" ]]; then
    user_home="$HOME"
  fi
  
  # Replace home path and username to prevent info leakage
  safe_sed_i "s|$user_home|~|g; s|$user_name|user|g" "$report_file"

  # Redact any GitHub Personal Access Tokens (PATs) and configuration tokens
  safe_sed_i -E "s/ghp_[A-Za-z0-9_]+/\[REDACTED\]/g" "$report_file"
  safe_sed_i -E "s/github_pat_[A-Za-z0-9_]+/\[REDACTED\]/g" "$report_file"

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
    safe_sed_i "s|$loaded_token|\[REDACTED\]|g" "$report_file"
  fi
  if [[ -n "${GITHUB_TOKEN:-}" && ${#GITHUB_TOKEN} -ge 4 ]]; then
    safe_sed_i "s|$GITHUB_TOKEN|\[REDACTED\]|g" "$report_file"
  fi
  
  # Upload using curl
  upload_url=$(curl -fsSL --data-binary @"$report_file" https://paste.rs || true)
  
  if [[ -n "$upload_url" && "$upload_url" == *"http"* ]]; then
    echo -e "${GREEN}Diagnostic report successfully shared!${NC}"
    echo -e "URL: ${BLUE}${upload_url}${NC}"
  else
    # report_file lives under a temp dir cleaned by the EXIT trap; copy it to
    # durable state (or /tmp) so the path we print still exists after exit.
    local_keep_dir="${XDG_STATE_HOME:-$user_home/.local/state}/millennium-helpers"
    mkdir -p "$local_keep_dir" 2>/dev/null || local_keep_dir="${TMPDIR:-/tmp}"
    kept_report="${local_keep_dir}/diag-share-failed-$(date +%Y%m%d%H%M%S).txt"
    if ! cp -f "$report_file" "$kept_report" 2>/dev/null; then
      # Copy failed: keep pointing at the temp file and disable cleanup so it survives.
      kept_report="$report_file"
      trap - EXIT INT TERM
    fi
    echo -e "${RED}Error: Failed to upload diagnostic report to paste.rs.${NC}" >&2
    echo -e "Local sanitized report kept at: ${YELLOW}${kept_report}${NC}" >&2
    echo -e "Tip: retry later, or paste the file contents into an offline pastebin." >&2
    if [[ -t 1 ]] && command -v xclip &>/dev/null; then
      echo -e "     Or copy with: ${YELLOW}xclip -selection clipboard < ${kept_report}${NC}" >&2
    elif [[ -t 1 ]] && command -v pbcopy &>/dev/null; then
      echo -e "     Or copy with: ${YELLOW}pbcopy < ${kept_report}${NC}" >&2
    fi
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
broken_hooks=()
missing_hooks=()
missing_completions=()
out_of_date_completions=()
broken_symlinks=()
TMP_SCRIPTS=""

# Used by sourced diag_report.sh (check_scripts_integrity).
# shellcheck disable=SC2034
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
USER_HOME="$(get_user_home "$RUNNING_USER")"
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
  for steam_dir in "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root" "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam" "${USER_HOME}/Library/Application Support/Steam"; do
    [[ -d "$steam_dir/logs" ]] || continue
    for log_name in "webhelper.txt" "webhelper-linux.txt" "console.txt" "console-linux.txt"; do
      if [[ -f "$steam_dir/logs/$log_name" ]]; then
        log_files+=("$steam_dir/logs/$log_name")
      fi
    done
  done
  
  if [[ ${#log_files[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No Steam logs found on this system.${NC}" >&2
    exit 1
  fi
  
  # Pick the newest log file
  latest_log=""
  latest_mtime=0
  for f in "${log_files[@]}"; do
    mtime=$(get_file_mtime "$f")
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

# Used by sourced diag_report.sh (check_update_timer).
# sysctl_user is provided by scripts/lib/logging.sh (via common.sh).

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

# shellcheck source=lib/diag_report.sh
if [[ -f "${_COMMON_LIB_DIR}/diag_report.sh" ]]; then
  source "${_COMMON_LIB_DIR}/diag_report.sh"
elif [[ -f "${SCRIPT_DIR}/lib/diag_report.sh" ]]; then
  # shellcheck source=lib/diag_report.sh
  source "${SCRIPT_DIR}/lib/diag_report.sh"
else
  echo "Error: Diagnostic report library not found." >&2
  exit 1
fi

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

# Actionable next steps for the default (read-only) report
if [[ "$COMMAND" != "doctor" ]]; then
  print_diag_next_steps
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

  # Issue 1: Out of date helper scripts (do this first so repairs run on new code)
  if [[ "$SCRIPTS_UP_TO_DATE" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Updating helper scripts...${NC}"
    if [[ "$(id -u)" -ne 0 ]]; then
      echo -e "${RED}Error: Root privileges are required to update helper scripts.${NC}" >&2
      echo -e "Please re-run the doctor with sudo: ${YELLOW}sudo $(basename "$0") doctor${NC}" >&2
    else
      for cmd_name in ${out_of_date_scripts[@]+"${out_of_date_scripts[@]}"}; do
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
    for item in ${broken_hooks[@]+"${broken_hooks[@]}"}; do
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
    for item in ${missing_hooks[@]+"${missing_hooks[@]}"}; do
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
  if [[ -n "$sched_path" ]]; then
    if [[ "$SYSTEMD_BOOTED" == "true" ]]; then
      echo -e "\n${YELLOW}[DOCTOR] Refreshing daily systemd user timer...${NC}"
      if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
        execute runuser -l "$RUNNING_USER" -c "${sched_path} enable $UPDATE_CHANNEL" || true
      else
        execute "${sched_path}" enable "$UPDATE_CHANNEL" || true
      fi
    else
      echo -e "\n${YELLOW}[DOCTOR] Refreshing daily cron update job...${NC}"
      if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
        execute runuser -l "$RUNNING_USER" -c "${sched_path} enable $UPDATE_CHANNEL --cron" || true
      else
        execute "${sched_path}" enable "$UPDATE_CHANNEL" --cron || true
      fi
    fi
  else
    echo -e "\n${YELLOW}[DOCTOR] Skip refreshing daily scheduler (millennium-schedule utility not found)${NC}"
  fi

  # Issue 7: Disabled systemd user lingering (Only on systemd booted)
  if [[ "$SYSTEMD_BOOTED" == "true" && "$LINGER_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Enabling systemd user lingering to run updates in the background...${NC}"
    execute loginctl enable-linger "${RUNNING_USER}"
  fi

  # Issue 8: Incorrect directory permissions or ownership
  if [[ "$PERMISSIONS_OK" == false ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Repairing directory permissions and ownership...${NC}"
    for dir in ${unwritable_dirs[@]+"${unwritable_dirs[@]}"}; do
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
    for local_path in ${missing_completions[@]+"${missing_completions[@]}"} ${out_of_date_completions[@]+"${out_of_date_completions[@]}"}; do
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
    for symlink_item in ${broken_symlinks[@]+"${broken_symlinks[@]}"}; do
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
    for f in ${obsolete_files_found[@]+"${obsolete_files_found[@]}"}; do
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
fi

exit 0
