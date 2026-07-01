#!/usr/bin/env bash
# De-register and purge Millennium client from Steam
set -euo pipefail

# Text color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

if pgrep -x steam >/dev/null 2>&1; then
  echo -e "${RED}Error: Close Steam completely before purging Millennium.${NC}" >&2
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}=== DRY RUN MODE: No changes will be made ===${NC}"
fi

echo -e "${BLUE}Purging Millennium hooks and files...${NC}"

execute() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would run:${NC} $*"
  else
    "$@"
  fi
}

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
        rm -rf "${cache_dir}/"*
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
