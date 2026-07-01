#!/usr/bin/env bash
# De-register and purge Millennium client from Steam
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

DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$DRY_RUN" == "false" ]] && [[ "$(id -u)" -ne 0 ]]; then
  echo -e "${RED}Error: This script must be run with sudo to remove system-wide files.${NC}" >&2
  echo -e "Please run: sudo $0" >&2
  exit 1
fi

# Helpers loaded

RUNNING_USER="${SUDO_USER:-$(id -un)}"

if pgrep -x steam >/dev/null 2>&1; then
  if is_game_running; then
    echo -e "${RED}Error: A Steam game is currently running. Purging cannot proceed while a game is active.${NC}" >&2
    exit 1
  fi

  echo "Steam is currently running. Closing Steam gracefully to apply purge..."
  if [[ "$DRY_RUN" == "false" ]]; then
    close_steam_gracefully "$RUNNING_USER"
  fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}=== DRY RUN MODE: No changes will be made ===${NC}"
fi

echo -e "${BLUE}Purging Millennium hooks and files...${NC}"

# execute resolved from common.sh

# 1. Clean up bootstrap symlinks and htmlcache for all users
getent passwd | while IFS=: read -r _ _ uid _ _ home _; do
  [[ "$uid" -ge 1000 ]] || continue
  
  # Find all Steam directories (native, Debian, and Flatpak candidates)
  for steam_dir in "$home/.local/share/Steam" "$home/.steam/steam" "$home/.steam/root" "$home/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [[ -d "$steam_dir" ]] || continue
    
    # Check and remove 32-bit bootstrap hook
    hook32="${steam_dir}/ubuntu12_32/libXtst.so.6"
    if [[ -L "$hook32" ]]; then
      target=$(readlink "$hook32")
      if [[ "$target" == *"/usr/lib/millennium"* ]]; then
        echo "Removing 32-bit hook: $hook32"
        execute rm -f "$hook32"
      fi
    fi
    
    # Check and remove 64-bit bootstrap hook
    hook64="${steam_dir}/ubuntu12_64/libXtst.so.6"
    if [[ -L "$hook64" ]]; then
      target=$(readlink "$hook64")
      if [[ "$target" == *"/usr/lib/millennium"* ]]; then
        echo "Removing 64-bit hook: $hook64"
        execute rm -f "$hook64"
      fi
    fi

    # Clear htmlcache to ensure vanilla Steam starts cleanly
    cache_dir="${steam_dir}/config/htmlcache"
    if [[ -d "$cache_dir" ]]; then
      echo "Clearing Steam htmlcache: $cache_dir"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Would remove all files in:${NC} ${cache_dir}/"
      else
        rm -rf "${cache_dir:?}/"*
      fi
    fi
  done
done

# 2. Remove Millennium binaries
if [[ -d "/usr/lib/millennium" ]]; then
  echo "Removing Millennium system directory: /usr/lib/millennium"
  execute rm -rf "/usr/lib/millennium"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${GREEN}Dry run completed successfully!${NC}"
else
  echo -e "${GREEN}Millennium has been successfully purged from Steam!${NC}"
fi
