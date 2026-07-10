#!/usr/bin/env bash
# De-register and purge Millennium client from Steam
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

DRY_RUN=false
QUIET=false
ASSUME_YES=false

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

De-register and purge Millennium client hooks and files from Steam.

Options:
  -d, --dry-run  Simulate operations without modifying files
  -q, --quiet    Suppress informational output
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
    -q|--quiet)
      export QUIET=true
      export MILLENNIUM_QUIET=1
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
      echo "Try '$(basename "$0") --help' for usage." >&2
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
    print_game_running_tip "purge Millennium"
    exit 1
  fi

  echo "Steam is currently running and must be closed to apply the purge."
  if [[ "$DRY_RUN" == "false" ]]; then
    confirm_close_steam "$RUNNING_USER" "${ASSUME_YES:-false}" || exit 1
  else
    echo -e "${YELLOW}[DRY RUN] Would confirm and close Steam before purging.${NC}"
  fi
fi

# Disable auto-update scheduler so it cannot reinstall after purge.
# Prefer PATH, then a sibling wrapper, then the .sh source (dev checkout).
# sched_bin may be "bash /path/to/….sh" — intentional word-split via SC2086.
sched_bin="$(command -v millennium-schedule 2>/dev/null || true)"
if [[ -z "$sched_bin" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "${script_dir}/millennium-schedule" ]]; then
    sched_bin="${script_dir}/millennium-schedule"
  elif [[ -f "${script_dir}/millennium-schedule.sh" ]]; then
    sched_bin="bash ${script_dir}/millennium-schedule.sh"
  fi
fi
if [[ -n "$sched_bin" ]]; then
  echo -e "${BLUE}Disabling Millennium auto-update scheduler (if configured)...${NC}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would run: millennium schedule disable${NC}"
  else
    # shellcheck disable=SC2086  # see sched_bin note above
    $sched_bin disable >/dev/null 2>&1 || true
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
  echo -e "Tip: remove helper tools with ${YELLOW}sudo ./install.sh uninstall${NC} if you no longer need them."
  echo -e "     Scheduler tip: ${YELLOW}millennium schedule status${NC} should now report disabled."
fi
