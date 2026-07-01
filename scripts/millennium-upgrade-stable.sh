#!/usr/bin/env bash
# Install official Millennium v3.2.0 stable over the chaotic-aur beta package.
set -euo pipefail

# Check dependencies
for cmd in curl tar awk sha256sum; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required dependency '$cmd' is not installed." >&2
    exit 1
  fi
done

FORCE=false
DRY_RUN=false
ROLLBACK=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE=true
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -r|--rollback)
      ROLLBACK=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$DRY_RUN" == "false" ]] && [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

# --- Rollback Execution ---
if [[ "$ROLLBACK" == "true" ]]; then
  dest_dir="/usr/lib/millennium"
  dest_bak="${dest_dir}.bak"
  
  if [[ ! -d "$dest_bak" ]]; then
    echo "Error: No backup directory found at ${dest_bak} to roll back to." >&2
    exit 1
  fi
  
  echo "Rolling back Millennium to the previous version..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "[DRY RUN] Would swap ${dest_dir} with ${dest_bak}"
  else
    dest_tmp="${dest_dir}.rollback_tmp"
    rm -rf "$dest_tmp"
    mv "$dest_dir" "$dest_tmp"
    mv "$dest_bak" "$dest_dir"
    mv "$dest_tmp" "$dest_bak"
    echo "Rollback successful! Previous version is now active."
  fi
  exit 0
fi

failure_handler() {
  local exit_code=$?
  if [[ "$DRY_RUN" == "false" ]]; then
    send_notification "Millennium Update Failed" "An error occurred during the update process (exit code: $exit_code)."
  fi
}
trap 'failure_handler' ERR



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
  echo -e "${RED}Error: Shared helper library not found.${NC}" >&2
  exit 1
fi
# Detect if Steam is running and handle it
RELAUNCH_STEAM=false

if pgrep -x steam >/dev/null 2>&1; then
  if is_game_running; then
    echo "Error: A Steam game is currently running. Upgrade cannot proceed while a game is active." >&2
    exit 1
  fi

  echo "Steam is currently running. Closing Steam gracefully to apply update..."
  
  # Capture env and command line arguments
  capture_steam_env "$RUNNING_USER" "/tmp/millennium-relaunch-${RUNNING_USER}"

  if [[ "$DRY_RUN" == "false" ]]; then
    close_steam_gracefully "$RUNNING_USER"
  fi
  RELAUNCH_STEAM=true
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

check_network() {
  local retries=5
  local wait_sec=10
  echo "Checking network connectivity..."
  for ((i=1; i<=retries; i++)); do
    if curl -sIk "https://github.com" &>/dev/null; then
      return 0
    fi
    echo "Network offline, retrying in ${wait_sec}s ($i/$retries)..." >&2
    sleep "$wait_sec"
  done
  echo "Error: Network is offline. Aborting." >&2
  exit 1
}

check_network

# Configure curl headers for GitHub API
CURL_HEADERS=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  CURL_HEADERS+=("-H" "Authorization: token $GITHUB_TOKEN")
fi

echo "Fetching latest Millennium stable release tag..."
TAG=""
if command -v jq &>/dev/null; then
  TAG=$(curl -sL "${CURL_HEADERS[@]}" --retry 3 --retry-delay 2 "https://api.github.com/repos/SteamClientHomebrew/Millennium/releases/latest" | jq -r '.tag_name' || true)
else
  TAG=$(python3 -c '
import urllib.request, json, os
try:
    headers = {"User-Agent": "Mozilla/5.0"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"token {token}"
    req = urllib.request.Request("https://api.github.com/repos/SteamClientHomebrew/Millennium/releases/latest", headers=headers)
    with urllib.request.urlopen(req) as response:
        release = json.loads(response.read().decode())
        print(release.get("tag_name", ""))
except Exception:
    pass
' || true)
fi

if [[ -z "$TAG" || "$TAG" == "null" ]]; then
  echo "Error: Could not retrieve the latest stable version tag from GitHub." >&2
  exit 1
fi

VER="${TAG#v}"

if [[ "$FORCE" = false ]] && [[ -f "/usr/lib/millennium/version.txt" ]]; then
  INSTALLED_VER=$(cat "/usr/lib/millennium/version.txt")
  if [[ "$VER" == "$INSTALLED_VER" ]]; then
    echo "Millennium is already up to date (v${VER}). Use --force to reinstall."
    exit 0
  fi
fi

ARCHIVE="millennium-v${VER}-linux-x86_64.tar.gz"
URL="https://github.com/SteamClientHomebrew/Millennium/releases/download/v${VER}/${ARCHIVE}"
SHA_URL="https://github.com/SteamClientHomebrew/Millennium/releases/download/v${VER}/millennium-v${VER}-linux-x86_64.sha256"

echo "Fetching SHA256 checksum for Millennium v${VER}..."
SHA=$(curl -fsSL "${CURL_HEADERS[@]}" --retry 3 --retry-delay 2 "$SHA_URL" | awk '{print $1}' || true)

if [[ -z "$SHA" ]]; then
  echo "Error: Could not retrieve the SHA256 checksum for v${VER}." >&2
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}[DRY RUN] Would download archive: ${URL}${NC}"
  echo -e "${YELLOW}[DRY RUN] Expected SHA256: ${SHA}${NC}"
  echo -e "${YELLOW}[DRY RUN] Would clear /usr/lib/millennium/* and install new binaries${NC}"
else
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT INT TERM

  echo "Downloading Millennium v${VER}..."
  curl -fL "${CURL_HEADERS[@]}" --retry 3 --retry-delay 2 "$URL" -o "$TMP/$ARCHIVE"
  echo "${SHA}  ${ARCHIVE}" | (cd "$TMP" && sha256sum -c)

  echo "Installing to /usr/lib/millennium/..."
  tar -xzf "$TMP/$ARCHIVE" -C "$TMP"
  
  # Atomic directory swap
  dest_dir="/usr/lib/millennium"
  dest_tmp="${dest_dir}.tmp"
  dest_bak="${dest_dir}.bak"
  
  rm -rf "$dest_tmp"
  mkdir -p "$dest_tmp"
  find "$TMP/usr/lib/millennium/" -type f -exec install -m755 -t "$dest_tmp/" {} +
  echo "${VER}" > "$dest_tmp/version.txt"
  chmod 644 "$dest_tmp/version.txt"
  
  # Generate cryptographic integrity manifest
  (cd "$dest_tmp" && sha256sum libmillennium_bootstrap_x86.so libmillennium_bootstrap_hhx64.so libmillennium_x86.so libmillennium_hhx64.so libmillennium_pvs64 > checksums.txt)
  chmod 644 "$dest_tmp/checksums.txt"

  # Perform swap, keeping previous version in dest_bak
  if [[ -d "$dest_dir" ]]; then
    rm -rf "$dest_bak"
    mv "$dest_dir" "$dest_bak"
  fi
  
  if mv "$dest_tmp" "$dest_dir"; then
    echo "Millennium updated successfully."
  else
    echo "Error: Failed to swap directory. Restoring backup..." >&2
    if [[ -d "$dest_bak" ]]; then
      mv "$dest_bak" "$dest_dir"
    fi
    exit 1
  fi

  if command -v restorecon &>/dev/null; then
    echo "Restoring SELinux contexts for /usr/lib/millennium/..."
    restorecon -R /usr/lib/millennium/ || true
  fi
fi

# Re-link bootstrap hooks for all Steam users (same as pacman post_install)
getent passwd | while IFS=: read -r _ _ uid _ _ home _; do
  [[ "$uid" -ge 1000 ]] || continue
  
  # Find steam directory for this user
  steam_dir=""
  for cand in "$home/.local/share/Steam" "$home/.steam/steam" "$home/.steam/root" "$home/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    if [[ -d "$cand" ]]; then
      steam_dir="$cand"
      break
    fi
  done
  [[ -n "$steam_dir" ]] || continue
  
  execute mkdir -p "$steam_dir/ubuntu12_32" "$steam_dir/ubuntu12_64"
  execute ln -sf /usr/lib/millennium/libmillennium_bootstrap_x86.so   "$steam_dir/ubuntu12_32/libXtst.so.6"
  execute ln -sf /usr/lib/millennium/libmillennium_bootstrap_hhx64.so "$steam_dir/ubuntu12_64/libXtst.so.6"

  # Flatpak Steam warning
  if [[ "$steam_dir" == *"com.valvesoftware.Steam"* ]]; then
    echo "Note: Flatpak Steam detected. To allow Steam to load Millennium, make sure to run:"
    echo "  flatpak override --user --filesystem=/usr/lib/millennium com.valvesoftware.Steam"
  fi
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${GREEN}Dry run completed successfully!${NC}"
else
  echo "Installed Millennium v${VER} stable."
  send_notification "Millennium Updated" "Successfully updated to Millennium v${VER} (stable)."
  echo "Note: Settings may still fail on Steam public beta until Millennium issue #790 is fixed."
fi

if [[ "$RELAUNCH_STEAM" == "true" && "$DRY_RUN" == "false" ]]; then
  echo "Relaunching Steam..."
  
  # Source saved environment variables (sets DISPLAY, WAYLAND_DISPLAY, STEAM_ARGS, WAS_FLATPAK, etc.)
  # shellcheck disable=SC1090
  source "/tmp/millennium-relaunch-${RUNNING_USER}"
  rm -f "/tmp/millennium-relaunch-${RUNNING_USER}"

  if [[ "${WAS_FLATPAK:-false}" == "true" ]]; then
    runuser "$RUNNING_USER" -c "flatpak run com.valvesoftware.Steam ${STEAM_ARGS} >/dev/null 2>&1 &"
  else
    if command -v steam &>/dev/null; then
      runuser "$RUNNING_USER" -c "steam ${STEAM_ARGS} >/dev/null 2>&1 &"
    elif [[ -x "${USER_HOME}/.local/bin/steam" ]]; then
      runuser "$RUNNING_USER" -c "${USER_HOME}/.local/bin/steam ${STEAM_ARGS} >/dev/null 2>&1 &"
    fi
  fi
fi
