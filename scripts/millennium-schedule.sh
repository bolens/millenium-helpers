#!/usr/bin/env bash
# Configure systemd user timer for Millennium auto-updates
set -euo pipefail

# Text color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SERVICE_NAME="millennium-update.service"
TIMER_NAME="millennium-update.timer"
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_PATH="${USER_CONFIG_DIR}/${SERVICE_NAME}"
TIMER_PATH="${USER_CONFIG_DIR}/${TIMER_NAME}"

show_help() {
  cat << EOF
Usage: $(basename "$0") COMMAND [OPTIONS]

Commands:
  enable [stable|beta]  Enable the daily update user timer (defaults to stable)
  disable               Disable the update user timer and service
  status                Show status of the systemd user service and timer

Options:
  -d, --dry-run         Perform dry-run without writing files or changing systemd state
  -h, --help            Show this help message
EOF
}

# Parse options and commands
COMMAND=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    enable|disable|status)
      COMMAND="$1"
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
      if [[ "$COMMAND" == "enable" && ("$1" == "stable" || "$1" == "beta") ]]; then
        # Handle positional channel argument
        # We will parse it in the enable function
        break
      else
        echo -e "${RED}Unknown option: $1${NC}" >&2
        show_help
        exit 1
      fi
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

execute() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would run:${NC} $*"
  else
    "$@"
  fi
}

write_file() {
  local target="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would write file: ${target} with contents:${NC}"
    cat
  else
    cat > "$target"
  fi
}

enable_timer() {
  local channel="${1:-stable}"
  local script_file=""

  case "$channel" in
    stable)
      script_file="/usr/local/bin/millennium-upgrade-stable"
      ;;
    beta)
      script_file="/usr/local/bin/millennium-upgrade-beta"
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

  # Ensure user systemd config directory exists
  execute mkdir -p "$USER_CONFIG_DIR"

  echo -e "${BLUE}Creating systemd user service file...${NC}"
  write_file "$SERVICE_PATH" << EOF
[Unit]
Description=Auto-update Millennium client (${channel})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/sudo -n ${script_file}
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
}

case "$COMMAND" in
  enable)
    enable_timer "${1:-stable}"
    ;;
  disable)
    disable_timer
    ;;
  status)
    show_status
    ;;
esac
