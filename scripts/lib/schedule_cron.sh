# shellcheck shell=bash
# Schedule helpers for millennium-schedule.sh (schedule_cron.sh)

crontab_for_user() {
  if [[ "$(id -u)" -eq 0 && "$RUNNING_USER" != "root" ]]; then
    crontab -u "$RUNNING_USER" "$@"
  else
    crontab "$@"
  fi
}

enable_cron() {
  local channel
  channel="$(require_update_channel "${1:-${CONFIG_UPDATE_CHANNEL:-stable}}")" || exit 1
  local script_file=""

  script_file=$(resolve_packaged_helper_path "millennium-upgrade")

  if ! command -v crontab &>/dev/null; then
    echo -e "${RED}Error: 'crontab' command not found. Please install a cron daemon (e.g. cronie, fcron).${NC}" >&2
    exit 1
  fi

  local sched_self
  sched_self=$(resolve_packaged_helper_path "millennium-schedule")

  local theme_cmd
  theme_cmd=$(resolve_packaged_helper_path "millennium-theme")

  local state_dir="${XDG_STATE_HOME:-$USER_HOME/.local/state}/millennium-helpers"
  # Channel is allow-listed (stable|beta|main). Quote paths with printf %q for cron.
  local q_state q_sched q_script q_theme
  printf -v q_state '%q' "$state_dir"
  printf -v q_sched '%q' "$sched_self"
  printf -v q_script '%q' "$script_file"
  printf -v q_theme '%q' "$theme_cmd"
  local cron_cmd="0 2 * * * sleep \$(python3 -c 'import random; print(random.randint(0, 3600))') && mkdir -p ${q_state} && { MILLENNIUM_SCHEDULER=1 ${q_sched} pre-update && /usr/bin/sudo -n ${q_script} --channel ${channel} && ${q_theme} update && MILLENNIUM_SCHEDULER=1 ${q_sched} post-update; } >> ${q_state}/updater.log 2>&1"

  echo -e "${BLUE}Configuring daily crontab job for user ${RUNNING_USER}...${NC}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would append to crontab:${NC}\n  ${cron_cmd}"
  else
    local current_cron
    current_cron=$(crontab_for_user -l 2>/dev/null || true)
    local clean_cron
    clean_cron=$(echo "$current_cron" | grep -v "millennium-schedule" || true)

    if [[ -n "$clean_cron" ]]; then
      echo -e "${clean_cron}\n${cron_cmd}" | crontab_for_user -
    else
      echo -e "${cron_cmd}" | crontab_for_user -
    fi
    echo -e "${GREEN}Millennium cron job successfully configured to run daily!${NC}"
  fi
}

disable_cron() {
  if ! command -v crontab &>/dev/null; then
    return 0
  fi

  echo -e "${BLUE}Removing crontab entry...${NC}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would remove millennium-schedule entries from crontab${NC}"
  else
    local current_cron
    current_cron=$(crontab_for_user -l 2>/dev/null || true)

    if echo "$current_cron" | grep -q "millennium-schedule"; then
      local clean_cron
      clean_cron=$(echo "$current_cron" | grep -v "millennium-schedule" || true)
      if [[ -n "$clean_cron" ]]; then
        echo "$clean_cron" | crontab_for_user -
      else
        crontab_for_user -r || true
      fi
      echo -e "${GREEN}Millennium cron job removed.${NC}"
    else
      echo "No cron job found."
    fi
  fi
}
