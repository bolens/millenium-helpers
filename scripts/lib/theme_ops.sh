# shellcheck shell=bash
# Theme helpers for millennium-theme.sh (theme_ops.sh)

_sanitize_theme_component() {
  local value="$1"
  local label="$2"
  if [[ -z "$value" || "$value" == "." || "$value" == ".." || "$value" == */* ]]; then
    echo -e "${RED}Error: Invalid ${label} '${value}'.${NC}" >&2
    exit 1
  fi
}

_resolve_theme_dir() {
  local component="$1"
  local candidate="${SKINS_DIR}/${component}"
  local resolved resolved_skins
  resolved="$(portable_realpath_m "$candidate")"
  resolved_skins="$(portable_realpath_m "$SKINS_DIR")"
  if [[ "$resolved" != "$resolved_skins" && "$resolved" != "${resolved_skins}/"* ]]; then
    echo -e "${RED}Error: Resolved theme path '${resolved}' escapes the skins directory.${NC}" >&2
    exit 1
  fi
  echo "$resolved"
}

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
  parsed_meta=$(python3 - "$meta_file" <<'PY' 2>/dev/null || echo "::"
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(f"{d.get('owner', '')}:{d.get('repo', '')}:{d.get('commit', '')}")
except Exception:
    print("::")
PY
)
  local owner="${parsed_meta%%:*}"
  local rest="${parsed_meta#*:}"
  local repo="${rest%%:*}"
  local current_commit="${rest#*:}"

  if [[ -z "$owner" || -z "$repo" ]]; then
    echo -e "${RED}Error: Invalid metadata format in ${meta_file}.${NC}" >&2
    return 1
  fi
  _sanitize_theme_component "$owner" "theme owner"
  _sanitize_theme_component "$repo" "theme repo"

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
    if [[ -z "$TMP" || ! -d "$TMP" ]]; then
      echo -e "${RED}Error: Failed to create temporary directory for theme update.${NC}" >&2
      return 1
    fi
    local theme_tmp="${target_dir}.tmp"
    local theme_bak="${target_dir}.bak"

    rm -rf "$theme_tmp" "$theme_bak"

    if ! download_file "https://github.com/${owner}/${repo}/archive/${COMMIT}.zip" "$TMP/theme.zip" "Downloading theme package"; then
      rm -rf "$TMP"
      return 1
    fi

    if ! safe_extract_zip "$TMP/theme.zip" "$TMP"; then
      echo -e "${RED}Error: Failed to extract theme archive safely.${NC}" >&2
      rm -rf "$TMP"
      return 1
    fi
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
