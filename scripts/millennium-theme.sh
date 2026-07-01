#!/usr/bin/env bash
# Millennium Theme CLI Manager
set -euo pipefail

# Text color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
  cat << EOF
Usage: $(basename "$0") [COMMAND] [ARGUMENTS] [OPTIONS]

Commands:
  list                  List all installed Millennium themes
  install [owner/repo]  Install a theme from a GitHub repository
  update [theme-name]   Update an installed theme to its latest commit
  remove [theme-name]   Uninstall/remove an installed theme

Options:
  -d, --dry-run         Perform a dry-run (simulates operations without modifying files)
  -h, --help            Show this help message
EOF
}

COMMAND=""
ARG=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    list|install|update|remove)
      COMMAND="$1"
      shift
      if [[ "$COMMAND" != "list" && $# -gt 0 ]]; then
        ARG="$1"
        shift
      fi
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
      echo "Unknown option: $1" >&2
      show_help
      exit 1
      ;;
  esac
done

if [[ -z "$COMMAND" ]]; then
  show_help
  exit 1
fi

if [[ "$COMMAND" != "list" && -z "$ARG" ]]; then
  echo -e "${RED}Error: Argument required for command '${COMMAND}'.${NC}" >&2
  exit 1
fi

RUNNING_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$RUNNING_USER" | cut -d: -f6)"

# Find Steam directories
steam_candidates=(
  "${USER_HOME}/.local/share/Steam"
  "${USER_HOME}/.steam/steam"
  "${USER_HOME}/.steam/root"
  "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"
)

STEAM_DIR=""
for candidate in "${steam_candidates[@]}"; do
  if [[ -d "$candidate" ]]; then
    STEAM_DIR="$candidate"
    break
  fi
done

if [[ -z "$STEAM_DIR" ]]; then
  echo -e "${RED}Error: No Steam directory detected on this system.${NC}" >&2
  exit 1
fi

SKINS_DIR="${STEAM_DIR}/steamui/skins"

execute() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would run:${NC} $*"
  else
    "$@"
  fi
}

# --- Command Execution ---

# 1. LIST COMMAND
if [[ "$COMMAND" == "list" ]]; then
  echo -e "${BLUE}=== Installed Millennium Themes ===${NC}"
  if [[ ! -d "$SKINS_DIR" ]]; then
    echo "No themes skins directory found at ${SKINS_DIR}."
    exit 0
  fi
  
  found=false
  for dir in "$SKINS_DIR"/*; do
    [[ -d "$dir" ]] || continue
    theme_name=$(basename "$dir")
    found=true
    
    # Read metadata if exists
    meta_file="${dir}/metadata.json"
    if [[ -f "$meta_file" ]]; then
      owner=$(python3 -c "import json; print(json.load(open('$meta_file')).get('owner', ''))" 2>/dev/null || true)
      repo=$(python3 -c "import json; print(json.load(open('$meta_file')).get('repo', ''))" 2>/dev/null || true)
      commit=$(python3 -c "import json; print(json.load(open('$meta_file')).get('commit', ''))" 2>/dev/null || true)
      if [[ -n "$owner" && -n "$repo" ]]; then
        echo -e "  - ${GREEN}${theme_name}${NC} (${owner}/${repo} @ ${commit:0:7})"
        continue
      fi
    fi
    echo -e "  - ${GREEN}${theme_name}${NC} (Local / Manual Installation)"
  done
  
  if [[ "$found" == "false" ]]; then
    echo "No themes installed."
  fi
  exit 0
fi

# 2. INSTALL COMMAND
if [[ "$COMMAND" == "install" ]]; then
  if [[ "$ARG" != */* ]]; then
    echo -e "${RED}Error: Theme must be in 'owner/repo' format.${NC}" >&2
    exit 1
  fi
  
  owner="${ARG%%/*}"
  repo="${ARG#*/}"
  
  echo -e "Resolving repository: ${owner}/${repo}..."
  
  # Fetch latest commit SHA
  CURL_HEADERS=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_HEADERS+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi
  
  COMMIT=""
  if command -v jq &>/dev/null; then
    COMMIT=$(curl -fsSL --retry 3 --retry-delay 2 "${CURL_HEADERS[@]}" "https://api.github.com/repos/${owner}/${repo}/commits" | jq -r '.[0].sha' || true)
  else
    COMMIT=$(python3 -c "
import urllib.request, json, os
try:
    headers = {'User-Agent': 'Mozilla/5.0'}
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization'] = f'token {token}'
    req = urllib.request.Request('https://api.github.com/repos/${owner}/${repo}/commits', headers=headers)
    with urllib.request.urlopen(req) as response:
        print(json.loads(response.read().decode())[0].get('sha', ''))
except Exception:
    pass
" || true)
  fi
  
  if [[ -z "$COMMIT" ]]; then
    echo -e "${RED}Error: Could not retrieve latest commit info for ${owner}/${repo}. Check repository name or internet connection.${NC}" >&2
    exit 1
  fi
  
  target_dir="${SKINS_DIR}/${repo}"
  
  if [[ -d "$target_dir" ]]; then
    echo -e "${YELLOW}Warning: Theme directory '${repo}' already exists. Use update instead.${NC}" >&2
    exit 1
  fi
  
  echo "Downloading theme package..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would install ${owner}/${repo} to ${target_dir}${NC}"
  else
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT INT TERM
    
    curl -fsSL "${CURL_HEADERS[@]}" --retry 3 --retry-delay 2 "https://github.com/${owner}/${repo}/archive/${COMMIT}.zip" -o "$TMP/theme.zip"
    
    # Extract
    unzip -q "$TMP/theme.zip" -d "$TMP" || [[ $? -le 2 ]]
    if [[ ! -d "$TMP/${repo}-${COMMIT}" ]]; then
      echo -e "${RED}Error: Failed to extract theme zip.${NC}" >&2
      exit 1
    fi
    
    mkdir -p "$SKINS_DIR"
    cp -a "$TMP/${repo}-${COMMIT}/." "$target_dir/"
    
    # Save metadata
    cat > "$target_dir/metadata.json" <<EOF
{
    "commit": "${COMMIT}",
    "owner": "${owner}",
    "repo": "${repo}"
}
EOF
    
    # Ensure correct ownership
    chown -R "${RUNNING_USER}:${RUNNING_USER}" "$target_dir"
    echo -e "${GREEN}Successfully installed theme '${repo}'!${NC}"
  fi
  exit 0
fi

# 3. REMOVE COMMAND
if [[ "$COMMAND" == "remove" ]]; then
  target_dir="${SKINS_DIR}/${ARG}"
  if [[ ! -d "$target_dir" ]]; then
    echo -e "${RED}Error: Theme '${ARG}' is not installed.${NC}" >&2
    exit 1
  fi
  
  echo "Removing theme '${ARG}'..."
  execute rm -rf "$target_dir"
  echo -e "${GREEN}Theme '${ARG}' successfully removed.${NC}"
  exit 0
fi

# 4. UPDATE COMMAND
if [[ "$COMMAND" == "update" ]]; then
  target_dir="${SKINS_DIR}/${ARG}"
  if [[ ! -d "$target_dir" ]]; then
    echo -e "${RED}Error: Theme '${ARG}' is not installed.${NC}" >&2
    exit 1
  fi
  
  meta_file="${target_dir}/metadata.json"
  if [[ ! -f "$meta_file" ]]; then
    echo -e "${RED}Error: Theme '${ARG}' does not have GitHub metadata. Cannot update automatically.${NC}" >&2
    exit 1
  fi
  
  owner=$(python3 -c "import json; print(json.load(open('$meta_file')).get('owner', ''))" 2>/dev/null || true)
  repo=$(python3 -c "import json; print(json.load(open('$meta_file')).get('repo', ''))" 2>/dev/null || true)
  
  if [[ -z "$owner" || -z "$repo" ]]; then
    echo -e "${RED}Error: Invalid metadata format in ${meta_file}.${NC}" >&2
    exit 1
  fi
  
  echo -e "Checking updates for theme '${ARG}' (${owner}/${repo})...."
  
  CURL_HEADERS=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_HEADERS+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi
  
  COMMIT=""
  if command -v jq &>/dev/null; then
    COMMIT=$(curl -fsSL --retry 3 --retry-delay 2 "${CURL_HEADERS[@]}" "https://api.github.com/repos/${owner}/${repo}/commits" | jq -r '.[0].sha' || true)
  else
    COMMIT=$(python3 -c "
import urllib.request, json, os
try:
    headers = {'User-Agent': 'Mozilla/5.0'}
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization'] = f'token {token}'
    req = urllib.request.Request('https://api.github.com/repos/${owner}/${repo}/commits', headers=headers)
    with urllib.request.urlopen(req) as response:
        print(json.loads(response.read().decode())[0].get('sha', ''))
except Exception:
    pass
" || true)
  fi
  
  if [[ -z "$COMMIT" ]]; then
    echo -e "${RED}Error: Could not retrieve latest commit info from GitHub.${NC}" >&2
    exit 1
  fi
  
  current_commit=$(python3 -c "import json; print(json.load(open('$meta_file')).get('commit', ''))" 2>/dev/null || true)
  if [[ "$current_commit" == "$COMMIT" ]]; then
    echo -e "${GREEN}Theme '${ARG}' is already up to date.${NC}"
    exit 0
  fi
  
  echo -e "New commit found: ${COMMIT:0:7}. Updating..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would update theme '${ARG}' to commit ${COMMIT}${NC}"
  else
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT INT TERM
    
    curl -fsSL "${CURL_HEADERS[@]}" --retry 3 --retry-delay 2 "https://github.com/${owner}/${repo}/archive/${COMMIT}.zip" -o "$TMP/theme.zip"
    
    unzip -q "$TMP/theme.zip" -d "$TMP" || [[ $? -le 2 ]]
    if [[ ! -d "$TMP/${repo}-${COMMIT}" ]]; then
      echo -e "${RED}Error: Failed to extract theme archive.${NC}" >&2
      exit 1
    fi
    
    theme_tmp="${target_dir}.tmp"
    theme_bak="${target_dir}.bak"
    
    rm -rf "$theme_tmp" "$theme_bak"
    mkdir -p "$theme_tmp"
    cp -a "$TMP/${repo}-${COMMIT}/." "$theme_tmp/"
    
    cat > "$theme_tmp/metadata.json" <<EOF
{
    "commit": "${COMMIT}",
    "owner": "${owner}",
    "repo": "${repo}"
}
EOF
    
    chown -R "${RUNNING_USER}:${RUNNING_USER}" "$theme_tmp"
    
    mv "$target_dir" "$theme_bak"
    mv "$theme_tmp" "$target_dir"
    rm -rf "$theme_bak"
    
    echo -e "${GREEN}Successfully updated theme '${ARG}' to commit ${COMMIT:0:7}!${NC}"
  fi
  exit 0
fi
