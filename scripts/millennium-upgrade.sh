#!/usr/bin/env bash
# Install official Millennium (stable or beta) releases over system files.
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

# Check dependencies
for cmd in curl tar awk sha256sum; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required dependency '$cmd' is not installed." >&2
    exit 1
  fi
done

CHANNEL="${CONFIG_UPDATE_CHANNEL:-stable}"
FORCE=false
DRY_RUN=false
QUIET=false
ASSUME_YES=false
ROLLBACK=false
ROLLBACK_TARGET=""
LOCAL_FILE=""

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install official Millennium (stable or beta) releases over system files.

Options:
  -c, --channel CHANNEL  Update channel: stable or beta (default: ${CONFIG_UPDATE_CHANNEL:-stable})
  --stable               Alias for --channel stable
  --beta                 Alias for --channel beta
  -r, --rollback [ID]    Roll back to a previous backup (or pass "list" to list backups)
  --file PATH            Install from a local archive instead of downloading
  -f, --force            Force reinstall even if already up to date
  -y, --yes              Skip confirmation when closing Steam
  -d, --dry-run          Simulate operations without modifying files
  -q, --quiet            Suppress informational output (warnings/errors still print)
  -V, --version          Show version information
  -h, --help             Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE=true
      shift
      ;;
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -q|--quiet)
      export QUIET=true
      export MILLENNIUM_QUIET=1
      shift
      ;;
    -c|--channel)
      if [[ $# -gt 1 ]]; then
        CHANNEL="$2"
        shift
      else
        echo "Error: --channel requires an argument (stable/beta)." >&2
        exit 1
      fi
      if [[ "$CHANNEL" != "stable" && "$CHANNEL" != "beta" ]]; then
        echo "Error: Invalid channel '$CHANNEL'. Must be stable or beta." >&2
        exit 1
      fi
      shift
      ;;
    --stable)
      CHANNEL="stable"
      shift
      ;;
    --beta)
      CHANNEL="beta"
      shift
      ;;
    -r|--rollback)
      ROLLBACK=true
      if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
        ROLLBACK_TARGET="$2"
        shift
      fi
      shift
      ;;
    --file)
      if [[ $# -gt 1 ]]; then
        LOCAL_FILE="$2"
        shift
      else
        echo "Error: --file requires an archive path argument." >&2
        exit 1
      fi
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

if [[ "$DRY_RUN" == "false" ]] && [[ "$ROLLBACK_TARGET" != "list" ]] && [[ "$(id -u)" -ne 0 ]] && [[ "$(uname)" != "Darwin" ]]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

# --- Rollback Execution ---
if [[ "$ROLLBACK" == "true" ]]; then
  perform_rollback "$ROLLBACK_TARGET"
  exit 0
fi

failure_handler() {
  local exit_code=$?
  if [[ "$DRY_RUN" == "false" ]]; then
    send_notification "Millennium Update Failed" "An error occurred during the update process (exit code: $exit_code)."
    print_upgrade_failure_tips "$exit_code"
  fi
}
trap 'failure_handler' ERR

RUNNING_USER="${SUDO_USER:-$(id -un)}"

# Detect if Steam is running and handle it
RELAUNCH_STEAM=false

if pgrep -x steam >/dev/null 2>&1; then
  if is_game_running; then
    echo "Error: A Steam game is currently running. Upgrade cannot proceed while a game is active." >&2
    print_game_running_tip "upgrade"
    exit 1
  fi

  echo "Steam is currently running and must be closed to apply the update."

  if [[ "$DRY_RUN" == "false" ]]; then
    capture_steam_env "$RUNNING_USER"
    confirm_close_steam "$RUNNING_USER" "${ASSUME_YES:-false}" || exit 1
  else
    echo -e "${YELLOW}[DRY RUN] Would capture Steam's environment and close it to apply the update.${NC}"
  fi
  RELAUNCH_STEAM=true
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}=== DRY RUN MODE: No changes will be made ===${NC}"
fi

if [[ -n "$LOCAL_FILE" ]]; then
  if [[ ! -f "$LOCAL_FILE" ]]; then
    echo "Error: Local archive file '${LOCAL_FILE}' does not exist." >&2
    exit 1
  fi
  VER=$(tar -xOzf "$LOCAL_FILE" usr/lib/millennium/version.txt 2>/dev/null || echo "local")
  echo "Using local file: ${LOCAL_FILE} (Version: ${VER})"
else
  check_network() {
    local retries=5
    local wait_sec="${MOCK_NETWORK_WAIT_SEC:-10}"
    echo "Checking network connectivity..."
    for ((i=1; i<=retries; i++)); do
      if curl -sIk "https://github.com" &>/dev/null; then
        return 0
      fi
      echo "Network offline, retrying in ${wait_sec}s ($i/$retries)..." >&2
      if [[ "$wait_sec" -gt 0 ]]; then
        sleep "$wait_sec"
      fi
    done
    echo "Error: Network is offline. Aborting." >&2
    exit 1
  }
  check_network

  if [[ "$CHANNEL" == "beta" ]]; then
    echo "Fetching latest Millennium beta release tag..."
    TAG=$(fetch_github_latest_beta_tag "SteamClientHomebrew" "Millennium")
  else
    echo "Fetching latest Millennium stable release tag..."
    TAG=$(fetch_github_latest_stable_tag "SteamClientHomebrew" "Millennium")
  fi

  if [[ -z "$TAG" || "$TAG" == "null" ]]; then
    echo "Error: Could not retrieve the latest ${CHANNEL} version tag from GitHub." >&2
    echo "If you are rate-limited, set a PAT: millennium schedule setup" >&2
    echo "  or: millennium-schedule config set github_token <token>" >&2
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
fi

if [[ -z "$LOCAL_FILE" ]]; then
  ARCHIVE="millennium-v${VER}-linux-x86_64.tar.gz"
  URL="https://github.com/SteamClientHomebrew/Millennium/releases/download/v${VER}/${ARCHIVE}"
  SHA_URL="https://github.com/SteamClientHomebrew/Millennium/releases/download/v${VER}/millennium-v${VER}-linux-x86_64.sha256"

  echo "Fetching SHA256 checksum for Millennium v${VER}..."
  SHA=$(curl -fsSL --retry 3 --retry-delay 2 "$SHA_URL" | awk '{print $1}' || true)

  if [[ -z "$SHA" ]]; then
    echo "Error: Could not retrieve the SHA256 checksum for v${VER}." >&2
    exit 1
  fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
  if [[ -n "$LOCAL_FILE" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would install local archive: ${LOCAL_FILE}${NC}"
  else
    echo -e "${YELLOW}[DRY RUN] Would download archive: ${URL}${NC}"
    echo -e "${YELLOW}[DRY RUN] Expected SHA256: ${SHA}${NC}"
  fi
  echo -e "${YELLOW}[DRY RUN] Would clear /usr/lib/millennium/* and install new binaries${NC}"
  prune_backups
else
  TMP=$(mktemp -d)
  if [[ -z "$TMP" || ! -d "$TMP" ]]; then
    echo "Error: Failed to create temporary directory for download." >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT INT TERM

  if [[ -n "$LOCAL_FILE" ]]; then
    cp "$LOCAL_FILE" "$TMP/millennium-local.tar.gz"
    ARCHIVE="millennium-local.tar.gz"
  else
    if ! download_file "$URL" "$TMP/$ARCHIVE" "Downloading Millennium v${VER}"; then
      exit 1
    fi
    echo "${SHA}  ${ARCHIVE}" | (cd "$TMP" && sha256sum -c)
  fi

  echo "Installing to /usr/lib/millennium/..."
  tar -xzf "$TMP/$ARCHIVE" -C "$TMP"
  
  # Atomic directory swap
  dest_dir="/usr/lib/millennium"
  dest_tmp="${dest_dir}.tmp"
  
  old_ver="unknown"
  if [[ -f "${dest_dir}/version.txt" ]]; then
    old_ver=$(cat "${dest_dir}/version.txt" | tr -d '[:space:]')
  fi
  if [[ -z "$old_ver" || "$old_ver" == "unknown" ]]; then
    old_ver=$(date +%Y%m%d%H%M%S)
  fi
  dest_bak="${dest_dir}.bak_${old_ver}"
  
  rm -rf "$dest_tmp"
  mkdir -p "$dest_tmp"
  
  extracted_dir="$TMP/usr/lib/millennium"
  if [[ ! -d "$extracted_dir" ]]; then
    extracted_dir="$TMP"
  fi
  find "$extracted_dir/" -type f -exec install -m755 -t "$dest_tmp/" {} + 2>/dev/null || true
  echo "${VER}" > "$dest_tmp/version.txt"
  chmod 644 "$dest_tmp/version.txt"
  
  (cd "$dest_tmp" && sha256sum libmillennium_bootstrap_x86.so libmillennium_bootstrap_hhx64.so libmillennium_x86.so libmillennium_hhx64.so libmillennium_pvs64 > checksums.txt 2>/dev/null || true)
  chmod 644 "$dest_tmp/checksums.txt" 2>/dev/null || true

  if [[ -d "$dest_dir" ]]; then
    rm -rf "$dest_bak"
    mv "$dest_dir" "$dest_bak"
  fi
  
  if mv "$dest_tmp" "$dest_dir"; then
    echo "Millennium updated successfully."
    prune_backups
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
if [[ "$(uname)" != "Darwin" ]] && command -v getent &>/dev/null; then
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
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${GREEN}Dry run completed successfully!${NC}"
else
  echo -e "${GREEN}Done.${NC} Installed Millennium v${VER} (${CHANNEL} channel)."
  if [[ "$RELAUNCH_STEAM" == "true" ]]; then
    echo "Steam will be relaunched."
  fi
  send_notification "Millennium Updated" "Successfully updated to Millennium v${VER} (${CHANNEL})."
  if [[ "$CHANNEL" == "stable" ]]; then
    echo "Note: Settings may still fail on Steam public beta until Millennium issue #790 is fixed."
  else
    echo "Start Steam with: ~/.local/bin/steam"
  fi
fi

if [[ "$RELAUNCH_STEAM" == "true" && "$DRY_RUN" == "false" ]]; then
  relaunch_steam "$RUNNING_USER"
  echo -e "${GREEN}Steam relaunched.${NC}"
fi
