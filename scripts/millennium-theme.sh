#!/usr/bin/env bash
# Millennium Theme CLI Manager
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
  -q, --quiet           Suppress informational output
  -y, --yes             Skip confirmation when removing a theme
  -V, --version         Show version information
  -h, --help            Show this help message

Examples:
  millennium theme install SteamClientHomebrew/millennium-steam-skin
  millennium-theme update --all
  millennium-theme remove millennium-steam-skin
EOF
}

COMMAND=""
ARG=""
DRY_RUN=false
QUIET=false
ASSUME_YES=false
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
    -V|--version)
      print_helpers_version
      exit 0
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      if [[ "$1" != -* ]]; then
        echo "Unknown command: $1" >&2
        suggestion="$(suggest_closest "$1" list install update remove || true)"
        if [[ -n "$suggestion" ]]; then
          echo "Did you mean '${suggestion}'?" >&2
        fi
      else
        echo "Unknown option: $1" >&2
      fi
      echo "Try '$(basename "$0") --help' for usage." >&2
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

# Phase 6e: list is Go-only (thin-wrap). Prefer checkout/install binary over PATH
# mocks used by the test suite.
resolve_millennium_go() {
  local cand
  for cand in \
    "${SCRIPT_DIR}/../bin/millennium" \
    "${SCRIPT_DIR}/millennium" \
    "$(command -v millennium 2>/dev/null || true)"
  do
    if [[ -n "$cand" && -x "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

run_theme_list_via_go() {
  local go_bin
  if ! go_bin="$(resolve_millennium_go)"; then
    echo -e "${RED}Error: theme list requires the Go millennium dispatcher (not found).${NC}" >&2
    echo "Install millennium-helpers or run 'make build' from a checkout." >&2
    exit 1
  fi
  local -a go_args=(theme list)
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    go_args+=(--json)
  fi
  if [[ "${QUIET:-false}" == "true" ]]; then
    go_args+=(--quiet)
  fi
  # Avoid re-entering this long-name helper if MILLENNIUM_LEGACY is set.
  MILLENNIUM_LEGACY=0 exec "$go_bin" "${go_args[@]}"
}

if [[ "$COMMAND" == "list" ]]; then
  run_theme_list_via_go
fi

RUNNING_USER="${SUDO_USER:-$(id -un)}"
USER_HOME="$(get_user_home "$RUNNING_USER")"

# Find Steam directories
steam_candidates=(
  "${USER_HOME}/.local/share/Steam"
  "${USER_HOME}/.steam/steam"
  "${USER_HOME}/.steam/root"
  "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"
  "${USER_HOME}/Library/Application Support/Steam"
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

# candidate theme directory and verifies it still resolves inside SKINS_DIR
# before any mkdir/cp/rm touches it (guards against SKINS_DIR itself
# containing an unexpected symlink).

# execute resolved from common.sh



# Feature modules (sourced by this entrypoint — no thin aggregator)
_feat_lib="${_COMMON_LIB_DIR:-${SCRIPT_DIR}/lib}"
if [[ ! -f "${_feat_lib}/theme_ops.sh" ]]; then
  _feat_lib="${SCRIPT_DIR}/lib"
fi
# shellcheck source=lib/theme_ops.sh
source "${_feat_lib}/theme_ops.sh"
unset _feat_lib

# --- Command Execution ---

# 1. INSTALL COMMAND
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
    echo -e "${RED}Error: Could not retrieve latest commit info for ${owner}/${repo}. Check repository name, network, or GitHub rate limits.${NC}" >&2
    echo -e "Tip: set a PAT via ${YELLOW}millennium schedule setup${NC} or ${YELLOW}millennium schedule config set github_token <token>${NC}." >&2
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
    if [[ -z "$TMP" || ! -d "$TMP" ]]; then
      echo -e "${RED}Error: Failed to create temporary directory for theme installation.${NC}" >&2
      exit 1
    fi
    trap 'rm -rf "$TMP"' EXIT INT TERM

    if ! download_file "https://github.com/${owner}/${repo}/archive/${COMMIT}.zip" "$TMP/theme.zip" "Downloading theme package"; then
      exit 1
    fi

    # Extract (reject zip-slip)
    if ! safe_extract_zip "$TMP/theme.zip" "$TMP"; then
      echo -e "${RED}Error: Failed to extract theme zip safely.${NC}" >&2
      exit 1
    fi
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
    echo -e "Next: enable it in Steam → Millennium → Themes (or Settings)."
    echo -e "Tip: ${YELLOW}millennium theme list${NC} shows installed themes; the active one is marked."
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

  # Warn if removing the active theme
  active_theme="Steam"
  steam_path=""
  for cand in \
    "${USER_HOME}/.local/share/Steam" \
    "${USER_HOME}/.steam/steam" \
    "${USER_HOME}/.steam/root" \
    "${USER_HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    if [[ -d "$cand" ]]; then
      steam_path="$cand"
      break
    fi
  done
  if [[ -n "$steam_path" ]]; then
    for cand in \
      "${USER_HOME}/.config/millennium/config.json" \
      "${steam_path}/millennium/config.json" \
      "${steam_path}/ext/config.json"; do
      if [[ -f "$cand" ]]; then
        active_theme=$(python3 -c "
import json
try:
    with open('$cand') as f:
        data = json.load(f)
        print(data.get('themes', {}).get('activeTheme', 'Steam'))
except Exception:
    print('Steam')
" 2>/dev/null || echo "Steam")
        break
      fi
    done
  fi

  if [[ "$ARG" == "$active_theme" ]]; then
    echo -e "${YELLOW}Warning: '${ARG}' is currently the active Millennium theme.${NC}"
  fi

  if [[ "$ASSUME_YES" != "true" && -t 0 && -z "${TEST_SUITE_RUN:-}" ]]; then
    printf "Remove theme '%s'? [y/N]: " "$ARG" >&2
    read -r reply || true
    case "$reply" in
      [Yy]|[Yy][Ee][Ss]) ;;
      *)
        echo "Aborted."
        exit 0
        ;;
    esac
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
      echo "Install one with: millennium theme install SteamClientHomebrew/millennium-steam-skin"
    fi
  else
    update_single_theme "$ARG"
  fi
  exit 0
fi
