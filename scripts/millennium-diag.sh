#!/usr/bin/env bash
# Diagnostics and status reporter for Millennium helper scripts
# State flags/arrays are consumed by sourced diag_*.sh modules (JSON + doctor).
# shellcheck disable=SC2034
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
UNMANAGED_FILES_OK=true
MIXED_INSTALL_OK=true
INSTALL_METHOD=""
HELPERS_CHECKOUT=""
LATEST_RELEASE_TAG=""
obsolete_files_found=()
unmanaged_files_found=()
DIAG_COMPLETION_PATHS=()
DIAG_COMPLETION_REPOS=()

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

# Used by sourced diag.sh (helper integrity / install checks).
# shellcheck disable=SC2034
UTILITIES=(
  "millennium-repair:scripts/millennium-repair.sh"
  "millennium-upgrade:scripts/millennium-upgrade.sh"
  "millennium-schedule:scripts/millennium-schedule.sh"
  "millennium-purge:scripts/millennium-purge.sh"
  "millennium-diag:scripts/millennium-diag.sh"
  "millennium-theme:scripts/millennium-theme.sh"
  "millennium-mcp:scripts/millennium-mcp.py"
  "millennium:scripts/millennium.sh"
)

# Shared library modules kept in sync with helper scripts on manual installs.
# (Pacman packages own these paths — doctor must not overwrite them.)
# shellcheck disable=SC2034
SHARED_MODULES=(
  "common.sh:scripts/common.sh"
  "lib/backup.sh:scripts/lib/backup.sh"
  "lib/diag.sh:scripts/lib/diag.sh"
  "lib/diag_ui.sh:scripts/lib/diag_ui.sh"
  "lib/diag_steam.sh:scripts/lib/diag_steam.sh"
  "lib/diag_env.sh:scripts/lib/diag_env.sh"
  "lib/diag_install.sh:scripts/lib/diag_install.sh"
  "lib/diag_release.sh:scripts/lib/diag_release.sh"
  "lib/diag_updates.sh:scripts/lib/diag_updates.sh"
  "lib/diag_completions.sh:scripts/lib/diag_completions.sh"
  "lib/diag_package_files.sh:scripts/lib/diag_package_files.sh"
  "lib/diag_next_steps.sh:scripts/lib/diag_next_steps.sh"
  "lib/diag_doctor_cleanup.sh:scripts/lib/diag_doctor_cleanup.sh"
  "lib/diag_doctor_scripts.sh:scripts/lib/diag_doctor_scripts.sh"
  "lib/diag_doctor_repair.sh:scripts/lib/diag_doctor_repair.sh"
  "lib/diag_doctor_completions.sh:scripts/lib/diag_doctor_completions.sh"
  "lib/diag_doctor.sh:scripts/lib/diag_doctor.sh"
  "lib/github.sh:scripts/lib/github.sh"
  "lib/logging.sh:scripts/lib/logging.sh"
  "lib/steam.sh:scripts/lib/steam.sh"
  "lib/version.sh:scripts/lib/version.sh"
  "VERSION:VERSION"
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

# Used by sourced diag.sh (scheduler / channel detection).
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

# shellcheck source=lib/diag.sh
if [[ -f "${_COMMON_LIB_DIR}/diag.sh" ]]; then
  source "${_COMMON_LIB_DIR}/diag.sh"
elif [[ -f "${SCRIPT_DIR}/lib/diag.sh" ]]; then
  # shellcheck source=lib/diag.sh
  source "${SCRIPT_DIR}/lib/diag.sh"
else
  echo "Error: Diagnostic library not found." >&2
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
  "unmanaged_files_ok": ${UNMANAGED_FILES_OK},
  "mixed_install_ok": ${MIXED_INSTALL_OK},
  "install_method": "${INSTALL_METHOD:-unknown}",
  "helpers_checkout": "${HELPERS_CHECKOUT:-}",
  "helpers_track": "${HELPERS_TRACK:-}",
  "helpers_ref": "${HELPERS_TRACK_REF:-}",
  "latest_release_tag": "${LATEST_RELEASE_TAG:-}",
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
  run_doctor_repairs
fi

exit 0
