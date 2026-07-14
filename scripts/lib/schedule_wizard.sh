# shellcheck shell=bash
# Schedule helpers for millennium-schedule.sh (schedule_wizard.sh)

run_setup_wizard() {
  if [[ ! -t 0 && "${FORCE_WIZARD:-}" != "true" ]]; then
    echo -e "${RED}Error: Setup wizard must be run in an interactive terminal.${NC}" >&2
    exit 1
  fi

  echo -e "\n${BLUE}=== Millennium Helpers Configuration Wizard ===${NC}"
  echo -e "This wizard will guide you through the configuration of the Millennium Helpers.\n"

  # 1. Release Channel Selection
  local default_ch_num="1"
  local default_ch_desc="Stable"
  if [[ "${CONFIG_UPDATE_CHANNEL:-}" == "beta" ]]; then
    default_ch_num="2"
    default_ch_desc="Beta"
  elif [[ "${CONFIG_UPDATE_CHANNEL:-}" == "main" ]]; then
    default_ch_num="3"
    default_ch_desc="Main"
  fi

  local channel=""
  while true; do
    echo -e "Choose Millennium Update Channel:"
    echo -e "  1) Stable   — latest published release"
    echo -e "  2) Beta     — beta-tagged prereleases"
    echo -e "  3) Main     — tip-of-development prereleases (non-beta when available)"
    printf "Selection [1-3, default: %s (%s)]: " "${default_ch_num}" "${default_ch_desc}" >&2
    read -r ch_sel
    [[ -z "$ch_sel" ]] && ch_sel="$default_ch_num"
    case "$ch_sel" in
      1)
        channel="stable"
        break
        ;;
      2)
        channel="beta"
        break
        ;;
      3)
        channel="main"
        break
        ;;
      *)
        echo -e "${RED}Invalid selection. Please choose 1, 2, or 3.${NC}\n"
        ;;
    esac
  done
  echo -e "Selected channel: ${GREEN}${channel}${NC}\n"

  # 2. Automated Daily Update Scheduler Timer
  local default_sched="y"
  local default_sched_desc="Y/n"

  local systemd_enabled=false
  if command -v systemctl &>/dev/null && sysctl_user is-enabled millennium-update.timer &>/dev/null; then
    systemd_enabled=true
  fi

  local cron_enabled=false
  if command -v crontab &>/dev/null && crontab_for_user -l 2>/dev/null | grep -q "millennium-schedule"; then
    cron_enabled=true
  fi

  if [[ "$systemd_enabled" == "true" || "$cron_enabled" == "true" ]]; then
    default_sched="y"
    default_sched_desc="Y/n"
  else
    local user_name="${SUDO_USER:-$(id -un)}"
    local user_home
    user_home="$(get_user_home "$user_name")"
    [[ -z "$user_home" ]] && user_home="$HOME"
    local user_config_dir="${XDG_CONFIG_HOME:-$user_home/.config}/millennium-helpers"
    if [[ -f "${user_config_dir}/config.json" ]]; then
      default_sched="n"
      default_sched_desc="y/N"
    fi
  fi

  local enable_sched=""
  while true; do
    printf "Would you like to enable the daily automated background update timer? [%s]: " "${default_sched_desc}" >&2
    read -r sched_sel
    [[ -z "$sched_sel" ]] && sched_sel="$default_sched"
    case "$sched_sel" in
      [Yy]|[Yy][Ee][Ss])
        enable_sched="true"
        break
        ;;
      [Nn]|[Nn][Oo])
        enable_sched="false"
        break
        ;;
      *)
        echo -e "${RED}Invalid option. Please enter y or n.${NC}\n"
        ;;
    esac
  done
  echo -e "Automated timer: ${GREEN}${enable_sched}${NC}\n"

  # 3. GitHub API Token configuration
  local github_token=""
  echo -e "To avoid GitHub API rate limits during updates, you can store an optional Personal Access Token (PAT)."
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo -e "A PAT is already saved. ${YELLOW}Press Enter to keep it${NC} (it will not be cleared), or paste a new token to replace it."
    printf "GitHub PAT [keep existing]: " >&2
    read -rs github_token
    echo "" >&2
    if [[ -z "$github_token" ]]; then
      github_token="$GITHUB_TOKEN"
      echo -e "Kept existing GitHub PAT (unchanged).\n"
    else
      echo -e "New GitHub PAT saved (hidden).\n"
    fi
  else
    echo -e "No PAT is configured yet. ${YELLOW}Press Enter to skip${NC}, or paste a token to save one."
    printf "GitHub PAT [optional]: " >&2
    read -rs github_token
    echo "" >&2
    if [[ -n "$github_token" ]]; then
      echo -e "GitHub PAT saved (hidden).\n"
    else
      echo -e "No GitHub PAT saved.\n"
    fi
  fi

  # Write configuration to the user's config directory
  local user_name="${SUDO_USER:-$(id -un)}"
  local user_home
  user_home="$(get_user_home "$user_name")"
  if [[ -z "$user_home" ]]; then
    user_home="$HOME"
  fi
  local user_config_dir="${XDG_CONFIG_HOME:-$user_home/.config}/millennium-helpers"

  if [[ "$DRY_RUN" == "false" ]]; then
    execute mkdir -p "$user_config_dir"
    execute chmod 700 "$user_config_dir"

    local config_file="${user_config_dir}/config.json"
    # Merge into existing config so backup_* and other keys are preserved.
    python3 - "$config_file" "$channel" "$github_token" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
channel = sys.argv[2]
token = sys.argv[3]
data = {}
if path.is_file():
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            data = {}
    except Exception:
        data = {}
data["update_channel"] = channel
data["github_token"] = token
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
    execute chmod 600 "$config_file"
    if [[ "$(id -u)" -eq 0 && "$user_name" != "root" ]]; then
      execute chown -R "${user_name}:${user_name}" "$user_config_dir"
    fi
    echo -e "\n${GREEN}Configuration saved successfully to:${NC} ${config_file}"
  else
    echo -e "\n${YELLOW}[DRY RUN] Would write config to ${user_config_dir}/config.json:${NC}"
    echo "update_channel: ${channel}"
    if [[ -n "$github_token" ]]; then
      echo "github_token: [set]"
    else
      echo "github_token: (not set)"
    fi
    echo "(other keys such as backup_limit are preserved)"
  fi

  # Reload configuration in memory
  export CONFIG_UPDATE_CHANNEL="$channel"
  export GITHUB_TOKEN="$github_token"

  # Trigger enablement of schedule if chosen
  if [[ "$enable_sched" == "true" ]]; then
    echo -e "\n${BLUE}Configuring background update scheduler...${NC}"
    if [[ "${USE_CRON:-false}" == "true" ]]; then
      enable_cron "$channel"
    else
      enable_timer "$channel"
    fi
  fi

  echo -e "\n${BLUE}Tip:${NC} tune backup retention anytime with:"
  echo -e "  millennium-schedule config set backup_limit 5"
  echo -e "  millennium-schedule config set backup_max_age_days 30"
}
