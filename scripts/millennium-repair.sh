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

SKIP_THEME=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--skip-theme)
      SKIP_THEME=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

USER_NAME="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"

STEAM=""
for candidate in "${USER_HOME}/.local/share/Steam" "${USER_HOME}/.steam/steam" "${USER_HOME}/.steam/root"; do
  if [[ -d "$candidate" ]]; then
    STEAM="$candidate"
    break
  fi
done
if [[ -z "$STEAM" ]]; then
  STEAM="${USER_HOME}/.local/share/Steam" # Fallback
fi

if pgrep -x steam >/dev/null 2>&1; then
  echo "Close Steam completely, then re-run: sudo $0" >&2
  exit 1
fi

echo "Fixing ownership..."
PATHS_TO_CHOWN=()
for path in "$STEAM/millennium" "$USER_HOME/.local/share/millennium" "$USER_HOME/.config/millennium"; do
  if [[ -d "$path" || -f "$path" ]]; then
    PATHS_TO_CHOWN+=("$path")
  fi
done
if [[ ${#PATHS_TO_CHOWN[@]} -gt 0 ]]; then
  chown -R "$USER_NAME:$USER_NAME" "${PATHS_TO_CHOWN[@]}"
fi

REFRESH_THEME=true
if [[ "$SKIP_THEME" = true ]]; then
  REFRESH_THEME=false
elif ! curl -sI "https://github.com" &>/dev/null; then
  echo "Warning: Network is offline. Skipping theme refresh." >&2
  REFRESH_THEME=false
fi

if [[ "$REFRESH_THEME" = true ]]; then
  echo "Fetching latest SpaceTheme/Steam commit SHA..."
  COMMIT=""
  
  # Configure curl headers for GitHub API
  CURL_HEADERS=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_HEADERS+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi

  if command -v jq &>/dev/null; then
    COMMIT=$(curl -fsSL "${CURL_HEADERS[@]}" "https://api.github.com/repos/SpaceTheme/Steam/commits/main" | jq -r '.sha' || true)
  else
    COMMIT=$(python3 -c '
import urllib.request, json, os
try:
    headers = {"User-Agent": "Mozilla/5.0"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"token {token}"
    req = urllib.request.Request("https://api.github.com/repos/SpaceTheme/Steam/commits/main", headers=headers)
    with urllib.request.urlopen(req) as response:
        commit = json.loads(response.read().decode())
        print(commit.get("sha", ""))
except Exception:
    pass
' || true)
  fi

  if [[ -z "$COMMIT" ]]; then
    COMMIT="9f5b9ea8fabc9cd3c4f46b638d78daa9c3da97dd"
    echo "Warning: Could not fetch latest commit from GitHub. Falling back to default: $COMMIT" >&2
  fi
  THEME_DIR="$STEAM/millennium/themes/Steam"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT INT TERM

  echo "Refreshing Steam theme..."
  curl -fsSL "${CURL_HEADERS[@]}" "https://github.com/SpaceTheme/Steam/archive/${COMMIT}.zip" -o "$TMP/theme.zip"
  
  # Allow unzip to return warnings (exit code <= 2) and verify extraction
  unzip -q "$TMP/theme.zip" -d "$TMP" || [[ $? -le 2 ]]
  if [[ ! -d "$TMP/Steam-${COMMIT}" ]]; then
    echo "Error: Failed to extract SpaceTheme archive." >&2
    exit 1
  fi
  
  rm -rf "$THEME_DIR"
  mkdir -p "$THEME_DIR"
  cp -a "$TMP/Steam-${COMMIT}/." "$THEME_DIR/"
  cat > "$THEME_DIR/metadata.json" <<EOF
{
    "commit": "${COMMIT}",
    "owner": "SpaceTheme",
    "repo": "Steam"
}
EOF
  chown -R "$USER_NAME:$USER_NAME" "$THEME_DIR"
fi

echo "Clearing htmlcache..."
rm -rf "$STEAM/config/htmlcache/"*

mkdir -p "$STEAM/ubuntu12_32" "$STEAM/ubuntu12_64"
ln -sf /usr/lib/millennium/libmillennium_bootstrap_x86.so   "$STEAM/ubuntu12_32/libXtst.so.6"
ln -sf /usr/lib/millennium/libmillennium_bootstrap_hhx64.so "$STEAM/ubuntu12_64/libXtst.so.6"

echo "Done. Start Steam with: ~/.local/bin/steam"
