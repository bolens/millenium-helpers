#!/usr/bin/env bash
# Fix Millennium settings panel and ownership. Close Steam first.
set -euo pipefail

# Check dependencies
for cmd in curl unzip; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required dependency '$cmd' is not installed." >&2
    exit 1
  fi
done

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

SKIP_THEME=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--skip-theme)
      SKIP_THEME=true
      shift
      ;;
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
  echo -e "${RED}Error: This script must be run with sudo to fix file ownership and link hooks.${NC}" >&2
  echo -e "Please run: sudo $0 $*" >&2
  exit 1
fi

USER_NAME="${SUDO_USER:-$(id -un)}"
USER_HOME="$(get_user_home "$USER_NAME")"

USER_XDG_CONFIG=""
USER_XDG_DATA=""
if [[ "$(id -u)" -eq 0 && "$USER_NAME" != "root" ]]; then
  # shellcheck disable=SC2016
  USER_XDG_CONFIG=$(runuser -l "$USER_NAME" -c 'echo "${XDG_CONFIG_HOME:-}"' 2>/dev/null || true)
  # shellcheck disable=SC2016
  USER_XDG_DATA=$(runuser -l "$USER_NAME" -c 'echo "${XDG_DATA_HOME:-}"' 2>/dev/null || true)
fi
if [[ -z "$USER_XDG_CONFIG" ]]; then
  USER_XDG_CONFIG="${XDG_CONFIG_HOME:-$USER_HOME/.config}"
fi
if [[ -z "$USER_XDG_DATA" ]]; then
  USER_XDG_DATA="${XDG_DATA_HOME:-$USER_HOME/.local/share}"
fi

STEAM=""
for candidate in "${USER_XDG_DATA}/Steam" "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root" "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
  if [[ -d "$candidate" ]]; then
    STEAM="$candidate"
    break
  fi
done
if [[ -z "$STEAM" ]]; then
  STEAM="${USER_HOME}/.local/share/Steam" # Fallback
fi

# Detect if Steam is running and handle it
RELAUNCH_STEAM=false

if pgrep -x steam >/dev/null 2>&1; then
  if is_game_running; then
    echo -e "${RED}Error: A Steam game is currently running. Repair cannot proceed while a game is active.${NC}" >&2
    exit 1
  fi

  echo "Steam is currently running. Closing Steam gracefully to apply repairs..."

  if [[ "$DRY_RUN" == "false" ]]; then
    # Capture env and command line arguments
    capture_steam_env "$USER_NAME"
    close_steam_gracefully "$USER_NAME"
  else
    echo -e "${YELLOW}[DRY RUN] Would capture Steam's environment and close it to apply repairs.${NC}"
  fi
  RELAUNCH_STEAM=true
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}=== DRY RUN MODE: No changes will be made ===${NC}"
fi

# Dry run wrappers resolved from common.sh

echo "Fixing ownership..."
PATHS_TO_CHOWN=()
for path in \
  "$STEAM/millennium" \
  "${USER_XDG_DATA}/millennium" \
  "$USER_HOME/.local/share/millennium" \
  "${USER_XDG_CONFIG}/millennium" \
  "$USER_HOME/.config/millennium" \
  "$USER_HOME/.var/app/com.valvesoftware.Steam/config/millennium" \
  "$USER_HOME/.var/app/com.valvesoftware.Steam/.config/millennium"; do
  if [[ -d "$path" || -f "$path" ]]; then
    PATHS_TO_CHOWN+=("$path")
  fi
done
if [[ ${#PATHS_TO_CHOWN[@]} -gt 0 ]]; then
  execute chown -R "$USER_NAME:$USER_NAME" "${PATHS_TO_CHOWN[@]}"
fi

# Detect the active theme name from Millennium config
ACTIVE_THEME="Steam"
CONFIG_JSON=""
for cand in \
  "${USER_XDG_CONFIG}/millennium/config.json" \
  "${USER_HOME}/.config/millennium/config.json" \
  "${USER_HOME}/.var/app/com.valvesoftware.Steam/config/millennium/config.json" \
  "${USER_HOME}/.var/app/com.valvesoftware.Steam/.config/millennium/config.json" \
  "${STEAM}/millennium/config.json" \
  "${STEAM}/ext/config.json"; do
  if [[ -f "$cand" ]]; then
    CONFIG_JSON="$cand"
    break
  fi
done

if [[ -n "$CONFIG_JSON" ]]; then
  parsed_theme=$(python3 -c "
import json
try:
    with open('$CONFIG_JSON') as f:
        data = json.load(f)
        print(data.get('themes', {}).get('activeTheme', 'Steam'))
except Exception:
    print('Steam')
" 2>/dev/null || echo "Steam")
  if [[ -n "$parsed_theme" ]]; then
    ACTIVE_THEME="$parsed_theme"
  fi
fi

THEME_DIR="$STEAM/millennium/themes/${ACTIVE_THEME}"

# Parse owner and repo from metadata.json if it exists
OWNER="SpaceTheme"
REPO="Steam"
HAS_METADATA=false

METADATA_FILE="${THEME_DIR}/metadata.json"
if [[ -f "$METADATA_FILE" ]]; then
  parsed_meta=$(python3 -c "
import json
try:
    with open('$METADATA_FILE') as f:
        data = json.load(f)
        print(f\"{data.get('owner', '')}:{data.get('repo', '')}\")
except Exception:
    print(':')
" 2>/dev/null || echo ":")
  parsed_owner="${parsed_meta%%:*}"
  parsed_repo="${parsed_meta#*:}"
  if [[ -n "$parsed_owner" && -n "$parsed_repo" ]]; then
    OWNER="$parsed_owner"
    REPO="$parsed_repo"
    HAS_METADATA=true
  fi
fi

REFRESH_THEME=true
if [[ "$SKIP_THEME" == "true" ]]; then
  REFRESH_THEME=false
elif [[ "$ACTIVE_THEME" != "Steam" && "$HAS_METADATA" == "false" ]]; then
  echo "Active theme '${ACTIVE_THEME}' does not have GitHub metadata. Skipping theme refresh."
  REFRESH_THEME=false
elif ! curl -sIk "https://github.com" &>/dev/null; then
  echo "Warning: Network is offline. Skipping theme refresh." >&2
  REFRESH_THEME=false
fi

if [[ "$REFRESH_THEME" == "true" ]]; then
  echo "Active Theme Detected: ${ACTIVE_THEME} (${OWNER}/${REPO})"
  echo "Fetching latest ${OWNER}/${REPO} commit SHA..."
  COMMIT=$(fetch_github_commit "$OWNER" "$REPO")

  if [[ -z "$COMMIT" ]]; then
    if [[ "$ACTIVE_THEME" == "Steam" ]]; then
      COMMIT="9f5b9ea8fabc9cd3c4f46b638d78daa9c3da97dd"
      echo "Warning: Could not fetch latest commit from GitHub. Falling back to default: $COMMIT" >&2
    else
      echo "Error: Could not retrieve the latest commit for active theme ${ACTIVE_THEME}." >&2
      exit 1
    fi
  fi
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would refresh active theme from GitHub commit: ${COMMIT}${NC}"
    echo -e "          Target theme folder: ${THEME_DIR}"
  else
    TMP="$(mktemp -d)"
    if [[ -z "$TMP" || ! -d "$TMP" ]]; then
      echo "Error: Failed to create temporary directory for theme refresh." >&2
      exit 1
    fi
    trap 'rm -rf "$TMP"' EXIT INT TERM

    if ! download_file "https://github.com/${OWNER}/${REPO}/archive/${COMMIT}.zip" "$TMP/theme.zip" "Refreshing active theme ${ACTIVE_THEME}"; then
      exit 1
    fi
    
    # Allow unzip to return warnings (exit code <= 2) and verify extraction
    unzip -q "$TMP/theme.zip" -d "$TMP" || [[ $? -le 2 ]]
    if [[ ! -d "$TMP/${REPO}-${COMMIT}" ]]; then
      echo "Error: Failed to extract theme archive." >&2
      exit 1
    fi
    
    # Atomic theme directory swap
    theme_tmp="${THEME_DIR}.tmp"
    theme_bak="${THEME_DIR}.bak"
    
    rm -rf "$theme_tmp" "$theme_bak"
    mkdir -p "$theme_tmp"
    cp -a "$TMP/${REPO}-${COMMIT}/." "$theme_tmp/"
    
    write_file "$theme_tmp/metadata.json" <<EOF
{
    "commit": "${COMMIT}",
    "owner": "${OWNER}",
    "repo": "${REPO}"
}
EOF
    chown -R "$USER_NAME:$USER_NAME" "$theme_tmp"

    if [[ -d "$THEME_DIR" ]]; then
      mv "$THEME_DIR" "$theme_bak"
    fi
    mv "$theme_tmp" "$THEME_DIR"
    rm -rf "$theme_bak"
  fi
fi

echo "Clearing htmlcache..."
if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}[DRY RUN] Would clear htmlcache files in:${NC} ${STEAM}/config/htmlcache/"
else
  rm -rf "$STEAM/config/htmlcache/"*
fi

execute mkdir -p "$STEAM/ubuntu12_32" "$STEAM/ubuntu12_64"
execute ln -sf /usr/lib/millennium/libmillennium_bootstrap_x86.so   "$STEAM/ubuntu12_32/libXtst.so.6"
execute ln -sf /usr/lib/millennium/libmillennium_bootstrap_hhx64.so "$STEAM/ubuntu12_64/libXtst.so.6"

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${GREEN}Dry run completed successfully!${NC}"
else
  echo "Done. Repair finished."
fi

if [[ "$RELAUNCH_STEAM" == "true" && "$DRY_RUN" == "false" ]]; then
  relaunch_steam "$USER_NAME"
fi
