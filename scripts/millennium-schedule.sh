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
USER_CONFIG_DIR="${HOME}/.config/systemd/user"
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
  -h, --help            Show this help message
EOF
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

  # Sanity check: Ensure scripts have been installed system-wide
  if [[ ! -f "$script_file" ]]; then
    echo -e "${RED}Error: Installed updater script not found at ${script_file}.${NC}" >&2
    echo -e "${YELLOW}Please run the installer first: sudo ./install.sh${NC}" >&2
    exit 1
  fi

  # Ensure user systemd config directory exists
  if [[ ! -d "$USER_CONFIG_DIR" ]]; then
    echo "Creating directory: $USER_CONFIG_DIR"
    mkdir -p "$USER_CONFIG_DIR"
  fi

  echo -e "${BLUE}Creating systemd user service file...${NC}"
  cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Auto-update Millennium client (${channel})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/sudo ${script_file}
EOF

  echo -e "${BLUE}Creating systemd user timer file...${NC}"
  cat > "$TIMER_PATH" << EOF
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
  systemctl --user daemon-reload

  echo -e "${BLUE}Enabling and starting ${TIMER_NAME}...${NC}"
  systemctl --user enable --now "$TIMER_NAME"

  echo -e "${GREEN}Millennium auto-update user timer (${channel}) has been enabled!${NC}"
  echo -e "It will run daily with a randomized delay of up to 1 hour."
  
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
  
  if systemctl --user is-active --quiet "$TIMER_NAME" || systemctl --user is-enabled --quiet "$TIMER_NAME" 2>/dev/null; then
    systemctl --user disable --now "$TIMER_NAME"
  fi
  
  if systemctl --user is-active --quiet "$SERVICE_NAME"; then
    systemctl --user stop "$SERVICE_NAME"
  fi

  if [[ -f "$TIMER_PATH" ]]; then
    echo "Removing timer file: $TIMER_PATH"
    rm -f "$TIMER_PATH"
  fi

  if [[ -f "$SERVICE_PATH" ]]; then
    echo "Removing service file: $SERVICE_PATH"
    rm -f "$SERVICE_PATH"
  fi

  echo -e "${BLUE}Reloading systemd user daemon...${NC}"
  systemctl --user daemon-reload

  echo -e "${GREEN}Millennium auto-update user timer and service have been disabled and removed.${NC}"
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

# Parse command
if [[ $# -lt 1 ]]; then
  show_help
  exit 1
fi

COMMAND="$1"
shift

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
  -h|--help)
    show_help
    exit 0
    ;;
  *)
    echo -e "${RED}Unknown command: $COMMAND${NC}" >&2
    show_help
    exit 1
    ;;
esac
