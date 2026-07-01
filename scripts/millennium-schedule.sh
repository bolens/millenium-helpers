#!/usr/bin/env bash
# Configure systemd user timer for Millennium auto-updates
set -euo pipefail

RUNNING_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$RUNNING_USER" | cut -d: -f6)"

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

SERVICE_NAME="millennium-update.service"
TIMER_NAME="millennium-update.timer"
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_PATH="${USER_CONFIG_DIR}/${SERVICE_NAME}"
TIMER_PATH="${USER_CONFIG_DIR}/${TIMER_NAME}"

show_help() {
  cat << EOF
Usage: $(basename "$0") COMMAND [OPTIONS]

Commands:
  enable [stable|beta]  Enable the daily update timer (defaults to stable)
  disable               Disable the update timer/cron and service
  status                Show status of the systemd user service and cron job

Options:
  -c, --cron            Force use of crontab instead of systemd
  -d, --dry-run         Perform dry-run without writing files or changing systemd state
  -h, --help            Show this help message
EOF
}

# Parse options and commands
COMMAND=""
DRY_RUN=false
USE_CRON=false
if [[ ! -d /run/systemd/system ]]; then
  USE_CRON=true
fi
CHANNEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    enable|disable|status|pre-update|post-update)
      COMMAND="$1"
      shift
      ;;
    stable|beta)
      CHANNEL="$1"
      shift
      ;;
    -c|--cron)
      USE_CRON=true
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

if [[ -z "$COMMAND" ]]; then
  show_help
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}=== DRY RUN MODE: No changes will be made ===${NC}"
fi

# execute and write_file resolved from common.sh

enable_timer() {
  local channel="${1:-stable}"
  local script_file=""

  case "$channel" in
    stable)
      script_file=$(resolve_helper_path "millennium-upgrade-stable")
      ;;
    beta)
      script_file=$(resolve_helper_path "millennium-upgrade-beta")
      ;;
    *)
      echo -e "${RED}Error: Invalid channel '$channel'. Choose 'stable' or 'beta'.${NC}" >&2
      exit 1
      ;;
  esac

  # Sanity check: Ensure scripts have been installed system-wide (only if not dry run)
  if [[ "$DRY_RUN" == "false" ]] && [[ ! -f "$script_file" ]]; then
    echo -e "${RED}Error: Installed updater script not found at ${script_file}.${NC}" >&2
    echo -e "${YELLOW}Please run the installer first: sudo ./install.sh${NC}" >&2
    exit 1
  fi

  local theme_cmd
  theme_cmd=$(resolve_helper_path "millennium-theme")

  local sched_self
  sched_self=$(resolve_helper_path "millennium-schedule")

  local state_dir="${XDG_STATE_HOME:-$USER_HOME/.local/state}/millennium-helpers"

  # Ensure user systemd config directory exists
  execute mkdir -p "$USER_CONFIG_DIR"

  echo -e "${BLUE}Creating systemd user service file...${NC}"
  write_file "$SERVICE_PATH" << EOF
[Unit]
Description=Auto-update Millennium client (${channel}) and themes
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'mkdir -p "${state_dir}" && { "${sched_self}" pre-update && /usr/bin/sudo -n "${script_file}" && "${theme_cmd}" update && "${sched_self}" post-update; } >> "${state_dir}/updater.log" 2>&1'
EOF

  echo -e "${BLUE}Creating systemd user timer file...${NC}"
  write_file "$TIMER_PATH" << EOF
[Unit]
Description=Trigger Millennium auto-update daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF

  echo -e "${BLUE}Reloading systemd user daemon...${NC}"
  execute systemctl --user daemon-reload

  echo -e "${BLUE}Enabling and starting ${TIMER_NAME}...${NC}"
  execute systemctl --user enable --now "$TIMER_NAME"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}Dry run: Timer enablement simulated successfully.${NC}"
  else
    echo -e "${GREEN}Millennium auto-update user timer (${channel}) has been enabled!${NC}"
    echo -e "It will run daily with a randomized delay of up to 1 hour."
  fi
  
  # Verify if passwordless sudo is active
  if ! sudo -n -l 2>/dev/null | grep -qE "NOPASSWD.*(millennium-upgrade-stable|ALL)"; then
    echo -e "\n${YELLOW}Warning: Passwordless sudo for the updater script could not be verified.${NC}"
    echo -e "Make sure you have run the installer first: sudo ./install.sh"
    echo -e "This configuration is required for the background timer to run successfully."
  else
    # Print sudo check info
    echo -e "\n${GREEN}Sudo Passwordless Configuration:${NC}"
    echo -e "The installer has automatically configured the required passwordless sudo rule at:"
    echo -e "  /etc/sudoers.d/millennium-helpers"
  fi
  
  # Print systemd user lingering tip
  echo -e "\n${GREEN}Systemd User Lingering (Optional):${NC}"
  echo -e "To allow user timers to run in the background even when you are logged out, enable user lingering:"
  echo -e "  loginctl enable-linger ${USER}"

  echo -e "\nYou can check the status of the timer with: millennium-schedule status"
}

disable_timer() {
  echo -e "${BLUE}Disabling and stopping Millennium update user timer and service...${NC}"
  
  if [[ "$DRY_RUN" == "false" ]]; then
    if systemctl --user is-active --quiet "$TIMER_NAME" || systemctl --user is-enabled --quiet "$TIMER_NAME" 2>/dev/null; then
      systemctl --user disable --now "$TIMER_NAME"
    fi
    
    if systemctl --user is-active --quiet "$SERVICE_NAME"; then
      systemctl --user stop "$SERVICE_NAME"
    fi
  else
    echo -e "${YELLOW}[DRY RUN] Would stop and disable timer: ${TIMER_NAME}${NC}"
    echo -e "${YELLOW}[DRY RUN] Would stop service: ${SERVICE_NAME}${NC}"
  fi

  if [[ -f "$TIMER_PATH" || "$DRY_RUN" == "true" ]]; then
    echo "Removing timer file: $TIMER_PATH"
    execute rm -f "$TIMER_PATH"
  fi

  if [[ -f "$SERVICE_PATH" || "$DRY_RUN" == "true" ]]; then
    echo "Removing service file: $SERVICE_PATH"
    execute rm -f "$SERVICE_PATH"
  fi

  echo -e "${BLUE}Reloading systemd user daemon...${NC}"
  execute systemctl --user daemon-reload

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}Dry run: Timer disablement simulated successfully.${NC}"
  else
    echo -e "${GREEN}Millennium auto-update user timer and service have been disabled and removed.${NC}"
  fi
}

show_status() {
  echo -e "${BLUE}=== Millennium User Update Timer Status ===${NC}"
  if [[ -f "$TIMER_PATH" ]]; then
    systemctl --user status "$TIMER_NAME" || true
  else
    echo -e "${YELLOW}Timer is not installed/configured.${NC}"
  fi

  echo -e "\n${BLUE}=== Millennium User Update Service Status ===${NC}"
  if [[ -f "$SERVICE_PATH" ]]; then
    systemctl --user status "$SERVICE_NAME" || true
  else
    echo -e "${YELLOW}Service is not installed/configured.${NC}"
  fi

  if command -v crontab &>/dev/null; then
    echo -e "\n${BLUE}=== Millennium Crontab Status ===${NC}"
    crontab -l 2>/dev/null | grep "millennium-schedule" || echo "No crontab entry configured."
  fi
}

pre_update() {
  log_info "Initiating pre-update checks..."
  if is_game_running; then
    log_warn "A game is currently running under Steam. Aborting update run."
    exit 75
  fi
  
  if pgrep -x steam >/dev/null; then
    log_info "Steam is running. Closing Steam gracefully to perform upgrades..."
    # Capture env
    capture_steam_env "$RUNNING_USER" "/tmp/millennium-relaunch-${RUNNING_USER}"
    
    # Close Steam
    close_steam_gracefully "$RUNNING_USER"
    log_info "Steam closed successfully."
  else
    log_info "Steam is not running. No close required."
  fi
  exit 0
}

post_update() {
  log_info "Initiating post-update checks and verification..."
  local state_file="/tmp/millennium-relaunch-${RUNNING_USER}"
  local diag_path
  diag_path=$(resolve_helper_path "millennium-diag")
  
  if ! "$diag_path" >/dev/null 2>&1; then
    log_error "Millennium update failed verification checks. Relaunch cancelled."
    rm -f "$state_file"
    exit 1
  fi
  
  log_info "Diagnostics verification passed successfully."
  if [[ -f "$state_file" ]]; then
    # Source saved environment variables (sets DISPLAY, WAYLAND_DISPLAY, STEAM_ARGS, WAS_FLATPAK, etc.)
    # shellcheck disable=SC1090
    source "$state_file"
    rm -f "$state_file"
    
    log_info "Relaunching Steam client with arguments: ${STEAM_ARGS:-none} (Flatpak: ${WAS_FLATPAK:-false})..."
    if [[ "${WAS_FLATPAK:-false}" == "true" ]]; then
      # shellcheck disable=SC2086
      flatpak run com.valvesoftware.Steam ${STEAM_ARGS} >/dev/null 2>&1 &
    else
      if command -v steam &>/dev/null; then
        # shellcheck disable=SC2086
        steam ${STEAM_ARGS} >/dev/null 2>&1 &
      elif [[ -x "${USER_HOME}/.local/bin/steam" ]]; then
        # shellcheck disable=SC2086
        "${USER_HOME}/.local/bin/steam" ${STEAM_ARGS} >/dev/null 2>&1 &
      fi
    fi
  else
    log_info "No saved relaunch state found. Steam will not be restarted."
  fi
  exit 0
}

enable_cron() {
  local channel="${1:-stable}"
  local script_file=""

  case "$channel" in
    stable)
      script_file=$(resolve_helper_path "millennium-upgrade-stable")
      ;;
    beta)
      script_file=$(resolve_helper_path "millennium-upgrade-beta")
      ;;
    *)
      echo -e "${RED}Error: Invalid channel '$channel'. Choose 'stable' or 'beta'.${NC}" >&2
      exit 1
      ;;
  esac

  if ! command -v crontab &>/dev/null; then
    echo -e "${RED}Error: 'crontab' command not found. Please install a cron daemon (e.g. cronie, fcron).${NC}" >&2
    exit 1
  fi

  local sched_self
  sched_self=$(resolve_helper_path "millennium-schedule")

  local theme_cmd
  theme_cmd=$(resolve_helper_path "millennium-theme")

  local state_dir="${XDG_STATE_HOME:-$USER_HOME/.local/state}/millennium-helpers"
  local cron_cmd="0 2 * * * sleep \$(python3 -c 'import random; print(random.randint(0, 3600))') && mkdir -p ${state_dir} && { ${sched_self} pre-update && /usr/bin/sudo -n ${script_file} && ${theme_cmd} update && ${sched_self} post-update; } >> ${state_dir}/updater.log 2>&1"
  
  echo -e "${BLUE}Configuring daily crontab job for user ${RUNNING_USER}...${NC}"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would append to crontab:${NC}\n  ${cron_cmd}"
  else
    local current_cron
    current_cron=$(crontab -l 2>/dev/null || true)
    local clean_cron
    clean_cron=$(echo "$current_cron" | grep -v "millennium-schedule" || true)
    
    if [[ -n "$clean_cron" ]]; then
      echo -e "${clean_cron}\n${cron_cmd}" | crontab -
    else
      echo -e "${cron_cmd}" | crontab -
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
    current_cron=$(crontab -l 2>/dev/null || true)
    
    if echo "$current_cron" | grep -q "millennium-schedule"; then
      local clean_cron
      clean_cron=$(echo "$current_cron" | grep -v "millennium-schedule" || true)
      if [[ -n "$clean_cron" ]]; then
        echo "$clean_cron" | crontab -
      else
        crontab -r || true
      fi
      echo -e "${GREEN}Millennium cron job removed.${NC}"
    else
      echo "No cron job found."
    fi
  fi
}

case "$COMMAND" in
  enable)
    if [[ "$USE_CRON" == "true" ]]; then
      enable_cron "${CHANNEL:-stable}"
    else
      enable_timer "${CHANNEL:-stable}"
    fi
    ;;
  disable)
    disable_timer
    disable_cron
    ;;
  status)
    show_status
    ;;
  pre-update)
    pre_update
    ;;
  post-update)
    post_update
    ;;
esac
