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
ASSUME_YES=false

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

De-register and purge Millennium client hooks and files from Steam.

Options:
  -d, --dry-run  Simulate operations without modifying files
  -y, --yes      Skip the interactive confirmation prompt
  -V, --version  Show version information
  -h, --help     Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -y|--yes)
      ASSUME_YES=true
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
      echo "Unknown option: $1" >&2
      show_help
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
elif [[ "$ASSUME_YES" != "true" ]]; then
  if [[ -t 0 ]]; then
    echo -e "${YELLOW}This will permanently remove Millennium hooks, binaries, and related Steam files.${NC}"
    read -rp "Are you sure you want to continue? [y/N]: " resp
    if [[ ! "$resp" =~ ^[Yy]$ ]]; then
      echo "Purge cancelled."
      exit 0
    fi
  else
    echo -e "${RED}Error: Refusing to purge without confirmation in a non-interactive session.${NC}" >&2
    echo -e "Re-run with ${YELLOW}--yes${NC} (or ${YELLOW}-y${NC}) to confirm, or use ${YELLOW}--dry-run${NC} to simulate." >&2
    exit 1
  fi
fi

echo -e "${BLUE}Purging Millennium hooks and files...${NC}"

# execute resolved from common.sh

# 1. Clean up bootstrap symlinks and htmlcache for all users
declare -a user_homes=()

if command -v getent &>/dev/null; then
  while IFS=: read -r _ _ uid _ _ home _; do
    if [[ "$uid" -ge 1000 ]]; then
      user_homes+=("$home")
    fi
  done < <(getent passwd)
else
  # macOS / fallback path
  for user_dir in /Users/*; do
    [[ -d "$user_dir" ]] || continue
    username=$(basename "$user_dir")
    if [[ "$username" != "Shared" && "$username" != "Guest" ]]; then
      user_homes+=("$user_dir")
    fi
  done
fi

# Bash 3.2 (macOS) treats "${arr[@]}" as unbound under set -u when empty.
# The ${arr[@]+"${arr[@]}"} idiom expands to nothing safely in that case.
for home in ${user_homes[@]+"${user_homes[@]}"}; do
  # Find all Steam directories (native, Debian, Flatpak, and macOS candidates)
  for steam_dir in "$home/.local/share/Steam" "$home/.steam/steam" "$home/.steam/root" "$home/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$home/Library/Application Support/Steam"; do
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
