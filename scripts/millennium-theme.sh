#!/usr/bin/env bash
# Millennium Theme CLI Manager
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

show_help() {
  cat << EOF
Usage: $(basename "$0") [COMMAND] [ARGUMENTS] [OPTIONS]

Commands:
  list                  List all installed Millennium themes
  install [owner/repo]  Install a theme from a GitHub repository
  update [theme-name]   Update an installed theme to its latest commit
  remove [theme-name]   Uninstall/remove an installed theme

Options:
  --json                Output list command results in structured JSON format
  -d, --dry-run         Perform a dry-run (simulates operations without modifying files)
  -h, --help            Show this help message
EOF
}

COMMAND=""
ARG=""
DRY_RUN=false
OUTPUT_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    list|install|update|remove)
      COMMAND="$1"
      shift
      if [[ "$COMMAND" != "list" && $# -gt 0 ]]; then
        # -a/--all are valid ARG values for 'update' even though they start
        # with '-'; anything else starting with '-' is treated as an option.
        if [[ "$1" != -* || "$1" == "-a" || "$1" == "--all" ]]; then
          ARG="$1"
          shift
        fi
      fi
      ;;
    --json)
      OUTPUT_JSON=true
      shift
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

if [[ "$COMMAND" != "list" && "$COMMAND" != "update" && -z "$ARG" ]]; then
  echo -e "${RED}Error: Argument required for command '${COMMAND}'.${NC}" >&2
  exit 1
fi

RUNNING_USER="${SUDO_USER:-$(id -un)}"
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

# Rejects theme/repo path components that could escape SKINS_DIR: empty,
# ".", "..", or containing an embedded "/" (a legitimate theme or repo name
# is always a single path segment). Without this, an install/remove/update
# argument like "x/../../../../tmp/evil-theme" would resolve outside of
# SKINS_DIR, letting the caller (including the MCP theme tool, which passes
# this argument through unchecked) write or delete arbitrary files the
# invoking user can access.
_sanitize_theme_component() {
  local value="$1"
  local label="$2"
  if [[ -z "$value" || "$value" == "." || "$value" == ".." || "$value" == */* ]]; then
    echo -e "${RED}Error: Invalid ${label} '${value}'.${NC}" >&2
    exit 1
  fi
}

# Defense-in-depth on top of _sanitize_theme_component: canonicalizes the
# candidate theme directory and verifies it still resolves inside SKINS_DIR
# before any mkdir/cp/rm touches it (guards against SKINS_DIR itself
# containing an unexpected symlink).
_resolve_theme_dir() {
  local component="$1"
  local candidate="${SKINS_DIR}/${component}"
  local resolved resolved_skins
  resolved="$(realpath -m -- "$candidate")"
  resolved_skins="$(realpath -m -- "$SKINS_DIR")"
  if [[ "$resolved" != "$resolved_skins" && "$resolved" != "${resolved_skins}/"* ]]; then
    echo -e "${RED}Error: Resolved theme path '${resolved}' escapes the skins directory.${NC}" >&2
    exit 1
  fi
  echo "$resolved"
}

# execute resolved from common.sh

update_single_theme() {
  local theme_name="$1"
  _sanitize_theme_component "$theme_name" "theme name"
  local target_dir
  target_dir="$(_resolve_theme_dir "$theme_name")"
  local meta_file="${target_dir}/metadata.json"
  
  if [[ ! -d "$target_dir" ]]; then
    echo -e "${RED}Error: Theme '${theme_name}' is not installed.${NC}" >&2
    return 1
  fi
  
  if [[ ! -f "$meta_file" ]]; then
    echo -e "${YELLOW}Theme '${theme_name}' does not have GitHub metadata. Skipping.${NC}"
    return 0
  fi
  
  local parsed_meta
  parsed_meta=$(python3 -c "
import json
try:
    with open('$meta_file') as f:
        d = json.load(f)
        print(f\"{d.get('owner', '')}:{d.get('repo', '')}:{d.get('commit', '')}\")
except Exception:
    print('::')
" 2>/dev/null || echo "::")
  local owner="${parsed_meta%%:*}"
  local rest="${parsed_meta#*:}"
  local repo="${rest%%:*}"
  local current_commit="${rest#*:}"
  
  if [[ -z "$owner" || -z "$repo" ]]; then
    echo -e "${RED}Error: Invalid metadata format in ${meta_file}.${NC}" >&2
    return 1
  fi
  
  echo -e "Checking updates for theme '${theme_name}' (${owner}/${repo})..."

  local COMMIT=""
  COMMIT=$(fetch_github_commit "$owner" "$repo")

  if [[ -z "$COMMIT" ]]; then
    echo -e "${RED}Error: Could not retrieve latest commit info from GitHub.${NC}" >&2
    return 1
  fi

  if [[ "$current_commit" == "$COMMIT" ]]; then
    echo -e "${GREEN}Theme '${theme_name}' is already up to date.${NC}"
    return 0
  fi

  echo -e "New commit found: ${COMMIT:0:7}. Updating..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would update theme '${theme_name}' to commit ${COMMIT}${NC}"
  else
    local TMP
    TMP="$(mktemp -d)"
    local theme_tmp="${target_dir}.tmp"
    local theme_bak="${target_dir}.bak"

    rm -rf "$theme_tmp" "$theme_bak"

    if ! download_file "https://github.com/${owner}/${repo}/archive/${COMMIT}.zip" "$TMP/theme.zip" "Downloading theme package"; then
      rm -rf "$TMP"
      return 1
    fi
    
    unzip -q "$TMP/theme.zip" -d "$TMP" || [[ $? -le 2 ]]
    if [[ ! -d "$TMP/${repo}-${COMMIT}" ]]; then
      echo -e "${RED}Error: Failed to extract theme archive.${NC}" >&2
      rm -rf "$TMP"
      return 1
    fi
    
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
    rm -rf "$TMP"
    
    echo -e "${GREEN}Successfully updated theme '${theme_name}' to commit ${COMMIT:0:7}!${NC}"
  fi
  return 0
}

# --- Command Execution ---

# 1. LIST COMMAND
if [[ "$COMMAND" == "list" ]]; then
  active_theme="Steam"
  if [[ "$OUTPUT_JSON" == "false" ]]; then
    echo -e "${BLUE}=== Installed Millennium Themes ===${NC}"
    
    # Active theme detection
    user_name="${SUDO_USER:-$(id -un)}"
    user_home="$(getent passwd "$user_name" | cut -d: -f6 || echo "")"
    if [[ -z "$user_home" ]]; then
      user_home="$HOME"
    fi
    user_xdg="${XDG_CONFIG_HOME:-$user_home/.config}"
    steam_path="${STEAM:-$user_home/.local/share/Steam}"
    config_json=""
    
    for cand in \
      "${user_xdg}/millennium/config.json" \
      "${user_home}/.config/millennium/config.json" \
      "${user_home}/.var/app/com.valvesoftware.Steam/config/millennium/config.json" \
      "${user_home}/.var/app/com.valvesoftware.Steam/.config/millennium/config.json" \
      "${steam_path}/millennium/config.json" \
      "${steam_path}/ext/config.json"; do
      if [[ -f "$cand" ]]; then
        config_json="$cand"
        break
      fi
    done
    
    if [[ -n "$config_json" ]]; then
      active_theme=$(python3 -c "
import json
try:
    with open('$config_json') as f:
        data = json.load(f)
        print(data.get('themes', {}).get('activeTheme', 'Steam'))
except Exception:
    print('Steam')
" 2>/dev/null || echo "Steam")
    fi
  fi

  if [[ ! -d "$SKINS_DIR" ]]; then
    if [[ "$OUTPUT_JSON" == "true" ]]; then
      echo "[]"
    else
      echo "No themes skins directory found at ${SKINS_DIR}."
    fi
    exit 0
  fi
  
  found=false
  first=true
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf "["
  fi
  
  for dir in "$SKINS_DIR"/*; do
    [[ -d "$dir" ]] || continue
    theme_name=$(basename "$dir")
    found=true
    
    owner=""
    repo=""
    commit=""
    type="local"
    
    # Read metadata if exists
    meta_file="${dir}/metadata.json"
    if [[ -f "$meta_file" ]]; then
      parsed_meta=$(python3 -c "
import json
try:
    with open('$meta_file') as f:
        d = json.load(f)
        print(f\"{d.get('owner', '')}:{d.get('repo', '')}:{d.get('commit', '')}\")
except Exception:
    print('::')
" 2>/dev/null || echo "::")
      owner="${parsed_meta%%:*}"
      rest="${parsed_meta#*:}"
      repo="${rest%%:*}"
      commit="${rest#*:}"
      if [[ -n "$owner" && -n "$repo" ]]; then
        type="github"
      fi
    fi
    
    if [[ "$OUTPUT_JSON" == "true" ]]; then
      if [[ "$first" == "false" ]]; then
        printf ","
      fi
      first=false
      if [[ "$type" == "github" ]]; then
        printf '{"name":"%s","owner":"%s","repo":"%s","commit":"%s","type":"github"}' "$theme_name" "$owner" "$repo" "$commit"
      else
        printf '{"name":"%s","type":"local"}' "$theme_name"
      fi
    else
      status_flag="[Installed]"
      status_color="${BLUE}"
      if [[ "$theme_name" == "$active_theme" ]]; then
        status_flag="[Active]   "
        status_color="${GREEN}"
      fi
      
      if [[ "$type" == "github" ]]; then
        printf "  %b%s%b  %-20s - %s/%s @ %s (GitHub)\n" \
          "$status_color" "$status_flag" "${NC}" \
          "$theme_name" \
          "$owner" "$repo" "${commit:0:7}"
      else
        printf "  %b%s%b  %-20s - Local / Manual Installation\n" \
          "$status_color" "$status_flag" "${NC}" \
          "$theme_name"
      fi
    fi
  done
  
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    echo "]"
  elif [[ "$found" == "false" ]]; then
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
  _sanitize_theme_component "$owner" "theme owner"
  _sanitize_theme_component "$repo" "theme repo"

  echo -e "Resolving repository: ${owner}/${repo}..."

  COMMIT=$(fetch_github_commit "$owner" "$repo")

  if [[ -z "$COMMIT" ]]; then
    echo -e "${RED}Error: Could not retrieve latest commit info for ${owner}/${repo}. Check repository name or internet connection.${NC}" >&2
    exit 1
  fi

  target_dir="$(_resolve_theme_dir "$repo")"

  if [[ -d "$target_dir" ]]; then
    echo -e "${YELLOW}Warning: Theme directory '${repo}' already exists. Use update instead.${NC}" >&2
    exit 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would install ${owner}/${repo} to ${target_dir}${NC}"
  else
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT INT TERM

    if ! download_file "https://github.com/${owner}/${repo}/archive/${COMMIT}.zip" "$TMP/theme.zip" "Downloading theme package"; then
      exit 1
    fi

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
  _sanitize_theme_component "$ARG" "theme name"
  target_dir="$(_resolve_theme_dir "$ARG")"
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
  if [[ -z "$ARG" || "$ARG" == "--all" || "$ARG" == "-a" ]]; then
    echo -e "${BLUE}=== Updating All Installed Themes ===${NC}"
    if [[ ! -d "$SKINS_DIR" ]]; then
      echo "No themes skins directory found at ${SKINS_DIR}."
      exit 0
    fi
    
    found_any=false
    for dir in "$SKINS_DIR"/*; do
      [[ -d "$dir" ]] || continue
      found_any=true
      theme_name=$(basename "$dir")
      update_single_theme "$theme_name" || true
      echo ""
    done
    
    if [[ "$found_any" == "false" ]]; then
      echo "No themes installed."
    fi
  else
    update_single_theme "$ARG"
  fi
  exit 0
fi
