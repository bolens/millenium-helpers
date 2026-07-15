#!/usr/bin/env bash
# Installation/uninstallation script for Millennium helper scripts.
set -euo pipefail

TARGET_DIR="${TARGET_DIR:-/usr/local/bin}"
LIB_DIR="${MILLENNIUM_LIB_DIR:-/usr/local/lib/millennium-helpers}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pre-parse track/tag for piped mode (before common.sh is available).
_PIPE_TRACK="${MILLENNIUM_HELPERS_TRACK:-release}"
_PIPE_TAG="${MILLENNIUM_HELPERS_TAG:-}"
_PIPE_ALLOW_UNSIGNED_MAIN=false
_pre_args=("$@")
while [[ ${#_pre_args[@]} -gt 0 ]]; do
  case "${_pre_args[0]}" in
    --track)
      _PIPE_TRACK="${_pre_args[1]:-}"
      _pre_args=("${_pre_args[@]:2}")
      ;;
    --track=*)
      _PIPE_TRACK="${_pre_args[0]#*=}"
      _pre_args=("${_pre_args[@]:1}")
      ;;
    --tag)
      _PIPE_TAG="${_pre_args[1]:-}"
      _PIPE_TRACK="tag"
      _pre_args=("${_pre_args[@]:2}")
      ;;
    --tag=*)
      _PIPE_TAG="${_pre_args[0]#*=}"
      _PIPE_TRACK="tag"
      _pre_args=("${_pre_args[@]:1}")
      ;;
    --allow-unsigned-main)
      _PIPE_ALLOW_UNSIGNED_MAIN=true
      _pre_args=("${_pre_args[@]:1}")
      ;;
    *)
      _pre_args=("${_pre_args[@]:1}")
      ;;
  esac
done
[[ -n "$_PIPE_TAG" ]] && _PIPE_TRACK="tag"
_PIPE_TRACK="$(printf '%s' "$_PIPE_TRACK" | tr '[:upper:]' '[:lower:]')"

# If running standalone/piped (e.g. curl ... | bash), download the helpers
# archive for the selected track and run the installer from there.
if [[ ! -f "${SCRIPT_DIR}/scripts/common.sh" ]]; then
  echo "Running in standalone/piped mode. Downloading helpers (track=${_PIPE_TRACK})..."
  TEMP_DIR=$(mktemp -d)
  if [[ -z "$TEMP_DIR" || ! -d "$TEMP_DIR" ]]; then
    echo "Error: Failed to create temporary directory for standalone installation." >&2
    exit 1
  fi
  trap 'rm -rf "$TEMP_DIR"' EXIT

  HELPERS_REPO="${HELPERS_GITHUB_REPO:-bolens/millenium-helpers}"
  IS_SOURCE=0
  if [[ -n "${MILLENNIUM_HELPERS_RELEASE_URL:-}" ]]; then
    echo "Warning: MILLENNIUM_HELPERS_RELEASE_URL overrides the download source (and matching SHA if provided)." >&2
    RELEASE_URL="$MILLENNIUM_HELPERS_RELEASE_URL"
    SHA_URL="${MILLENNIUM_HELPERS_RELEASE_SHA_URL:-${RELEASE_URL}.sha256}"
    NEEDS_SHA=1
  else
    case "$_PIPE_TRACK" in
      main)
        if [[ "$_PIPE_ALLOW_UNSIGNED_MAIN" != "true" && "${MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN:-}" != "1" ]]; then
          echo "Error: --track main installs an unsigned tip-of-main archive." >&2
          echo "Pass --allow-unsigned-main (or set MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN=1) to continue." >&2
          echo "Prefer a tagged release: --track release or --tag vX.Y.Z" >&2
          exit 1
        fi
        echo "Warning: tip-of-main install has no SHA256 sidecar (unsigned)." >&2
        RELEASE_URL="https://github.com/${HELPERS_REPO}/archive/refs/heads/main.tar.gz"
        SHA_URL=""
        NEEDS_SHA=0
        IS_SOURCE=1
        ;;
      tag|release|*)
        _pipe_arch=amd64
        case "$(uname -m 2>/dev/null || echo x86_64)" in
          aarch64 | arm64) _pipe_arch=arm64 ;;
        esac
        if [[ "$_PIPE_TRACK" == "tag" ]]; then
          _tag="$_PIPE_TAG"
          _tag="${_tag#v}"
          [[ -n "$_tag" ]] || { echo "Error: --tag required for track=tag" >&2; exit 1; }
        else
          _tag="$(
            curl -fsSL --retry 2 --retry-delay 1 \
              -H "User-Agent: millennium-helpers" \
              -H "Accept: application/vnd.github+json" \
              "https://api.github.com/repos/${HELPERS_REPO}/releases/latest" 2>/dev/null \
              | python3 -c "import json,sys; print((json.load(sys.stdin).get('tag_name') or '').lstrip('v'))" 2>/dev/null \
              || true
          )"
          [[ -n "$_tag" ]] || {
            echo "Error: could not resolve latest release tag for ${HELPERS_REPO}" >&2
            exit 1
          }
        fi
        RELEASE_URL="https://github.com/${HELPERS_REPO}/releases/download/v${_tag}/millennium-helpers-v${_tag}-linux-${_pipe_arch}.tar.gz"
        SHA_URL="${RELEASE_URL}.sha256"
        NEEDS_SHA=1
        ;;
    esac
  fi

  ARCHIVE="$TEMP_DIR/helpers-download.tar.gz"
  download_ok=false
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$RELEASE_URL" -o "$ARCHIVE"; then
      download_ok=true
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -qO "$ARCHIVE" "$RELEASE_URL"; then
      download_ok=true
    fi
  else
    echo "Error: curl or wget is required for standalone installation." >&2
    exit 1
  fi

  if [[ "$download_ok" != "true" || ! -s "$ARCHIVE" ]]; then
    echo "Error: Failed to download helpers archive from GitHub." >&2
    echo "URL: $RELEASE_URL" >&2
    exit 1
  fi

  if [[ "$NEEDS_SHA" -eq 1 ]]; then
    SHA_FILE="$TEMP_DIR/helpers-download.tar.gz.sha256"
    sha_ok=false
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL "$SHA_URL" -o "$SHA_FILE"; then
        sha_ok=true
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -qO "$SHA_FILE" "$SHA_URL"; then
        sha_ok=true
      fi
    fi
    if [[ "$sha_ok" != "true" || ! -s "$SHA_FILE" ]]; then
      echo "Error: Failed to download the SHA256 checksum sidecar." >&2
      echo "URL: $SHA_URL" >&2
      exit 1
    fi
    if ! command -v sha256sum >/dev/null 2>&1; then
      echo "Error: sha256sum is required to verify the release archive." >&2
      exit 1
    fi
    EXPECTED_SHA=$(awk '{print $1; exit}' "$SHA_FILE" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    ACTUAL_SHA=$(sha256sum "$ARCHIVE" | awk '{print $1}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [[ ! "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]]; then
      echo "Error: Checksum sidecar did not contain a valid SHA256 hash." >&2
      exit 1
    fi
    if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
      echo "Error: SHA256 mismatch for downloaded release archive." >&2
      echo "Expected: $EXPECTED_SHA" >&2
      echo "Actual:   $ACTUAL_SHA" >&2
      exit 1
    fi
    echo "SHA256 checksum verified."
  else
    echo "Tip-of-main archive: skipping release SHA256 sidecar."
  fi

  EXTRACT_ROOT="$TEMP_DIR"
  if ! tar -xzf "$ARCHIVE" -C "$TEMP_DIR"; then
    echo "Error: Failed to extract the helpers archive." >&2
    exit 1
  fi

  if [[ "$IS_SOURCE" -eq 1 ]]; then
    # GitHub source archives extract to millenium-helpers-main/
    for cand in "$TEMP_DIR"/millenium-helpers-main "$TEMP_DIR"/millenium-helpers-*; do
      if [[ -f "${cand}/install.sh" && -f "${cand}/scripts/common.sh" ]]; then
        EXTRACT_ROOT="$cand"
        break
      fi
    done
  fi

  if [[ ! -f "$EXTRACT_ROOT/install.sh" || ! -f "$EXTRACT_ROOT/scripts/common.sh" ]]; then
    echo "Error: Archive is missing install.sh or scripts/common.sh." >&2
    exit 1
  fi

  # Persist track for the re-exec'd installer (writes install-meta.json).
  export MILLENNIUM_HELPERS_TRACK="$_PIPE_TRACK"
  [[ -n "$_PIPE_TAG" ]] && export MILLENNIUM_HELPERS_TAG="$_PIPE_TAG"
  export MILLENNIUM_HELPERS_SOURCE_URL="$RELEASE_URL"

  bash "$EXTRACT_ROOT/install.sh" "$@"
  exit 0
fi

SUDOERS_FILE="${MOCK_SUDOERS_FILE:-/etc/sudoers.d/millennium-helpers}"

# Source shared helpers (color vars, execute, write_file)
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/scripts/common.sh"

# Feature helpers (long names). PATH entries are Go dispatcher argv0 twins
# (same binary as `millennium <cmd>`); shell scripts remain checkout fallbacks.
SCRIPTS=(
  "scripts/millennium-repair.sh:millennium-repair"
  "scripts/millennium-upgrade.sh:millennium-upgrade"
  "scripts/millennium-schedule.sh:millennium-schedule"
  "scripts/millennium-purge.sh:millennium-purge"
  "scripts/millennium-diag.sh:millennium-diag"
  "scripts/millennium-theme.sh:millennium-theme"
  "scripts/millennium-mcp.sh:millennium-mcp"
  # sentinel: install_scripts special-cases dest=millennium → Go binary
  ":millennium"
)

is_go_argv0_twin() {
  case "$1" in
    millennium|millennium-mcp|millennium-repair|millennium-upgrade|millennium-schedule|millennium-purge|millennium-diag|millennium-theme)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Ensure Go dispatcher binary exists under bin/millennium.
ensure_go_dispatcher() {
  local out="${SCRIPT_DIR}/bin/millennium"
  if [[ -x "$out" ]]; then
    return 0
  fi
  if [[ ! -d "${SCRIPT_DIR}/go/cmd/millennium" ]]; then
    return 1
  fi
  if ! command -v go >/dev/null 2>&1; then
    return 1
  fi
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  echo -e "${BLUE}Building Go dispatcher (bin/millennium)...${NC}"
  if make -C "$SCRIPT_DIR" build >/dev/null; then
    [[ -x "$out" ]]
    return $?
  fi
  return 1
}

die_go_dispatcher_required() {
  echo -e "${RED}Error: Go dispatcher (bin/millennium) is required to install PATH millennium.${NC}" >&2
  echo -e "Install a Go toolchain and re-run, or use a release archive that ships bin/millennium." >&2
  exit 1
}

# Sets DISPATCHER_SRC for TARGET_DIR/millennium.
# Returns 1 when Go is required but missing.
resolve_millennium_dispatcher() {
  local go_bin="${SCRIPT_DIR}/bin/millennium"
  if ensure_go_dispatcher && { [[ -x "$go_bin" ]] || [[ "${DRY_RUN:-false}" == "true" ]]; }; then
    DISPATCHER_SRC="$go_bin"
    return 0
  fi
  return 1
}

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS] [COMMAND]

Commands:
  install      Install helper tools to ${TARGET_DIR} (default, requires sudo)
  uninstall    Remove helper tools from ${TARGET_DIR} (requires sudo)

Options:
  -d, --dry-run      Perform dry-run without copying files or configuring sudoers
  -i, --install      Perform installation
  -u, --uninstall    Perform uninstallation
  -p, --purge        During uninstall, also purge all Millennium client files/hooks
      --track TRACK  Helpers install track: release (default), main (tip-of-main)
      --tag vX.Y.Z   Install a specific release tag (implies track=tag)
      --allow-unsigned-main
                     Required with --track main (no SHA256 sidecar)
  -V, --version      Show version information
  -h, --help         Show this help message

Environment:
  MILLENNIUM_HELPERS_TRACK / MILLENNIUM_HELPERS_TAG
  MILLENNIUM_HELPERS_RELEASE_URL / MILLENNIUM_HELPERS_RELEASE_SHA_URL
  MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN=1

Note: Release checksums are same-origin GitHub TOFU (archive + .sha256 from the
same release), not independent signing. Prefer package managers when available.

Note: Millennium client update channel (stable|beta|main) is separate; configure
via 'millennium schedule' / 'millennium upgrade --channel'.

Note: Install requires the Go dispatcher (prebuilt bin/millennium or build via
make build). Long-name shell helpers remain for MCP/timers/sudoers until command
peels finish; PATH millennium is always the Go binary.
EOF
}

check_root() {
  if [[ "$DRY_RUN" == "false" ]] && [[ "$(id -u)" -ne 0 ]]; then
    if [[ "$(uname)" == "Darwin" && -w "$TARGET_DIR" ]]; then
      return 0
    fi
    echo -e "${RED}Error: This script must be run with sudo to install system-wide to ${TARGET_DIR}.${NC}" >&2
    # Bash 3.2 (macOS): empty "${arr[*]}" is unbound under set -u.
    echo -e "Please run: sudo $0 ${ORIGINAL_ARGS[*]+${ORIGINAL_ARGS[*]}}" >&2
    exit 1
  fi
}

change_owner() {
  local recursive=""
  if [[ "$1" == "-R" ]]; then
    recursive="-R"
    shift
  fi
  local target="$1"
  local owner="${2:-root:root}"
  if [[ "$(id -u)" -eq 0 ]]; then
    if [[ "$(uname)" == "Darwin" && "$owner" == "root:root" ]]; then
      owner="root:wheel"
    fi
    if [[ -n "$recursive" ]]; then
      execute chown -R "$owner" "$target"
    else
      execute chown "$owner" "$target"
    fi
  fi
}

# Parse arguments
ORIGINAL_ARGS=("$@")
ACTION="install"
DRY_RUN=false
PURGE_REQUESTED=false
INSTALL_TRACK="${MILLENNIUM_HELPERS_TRACK:-release}"
INSTALL_TAG="${MILLENNIUM_HELPERS_TAG:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    install|-i|--install)
      ACTION="install"
      shift
      ;;
    uninstall|-u|--uninstall)
      ACTION="uninstall"
      shift
      ;;
    -p|--purge)
      PURGE_REQUESTED=true
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    --track)
      INSTALL_TRACK="${2:-}"
      shift 2
      ;;
    --track=*)
      INSTALL_TRACK="${1#*=}"
      shift
      ;;
    --tag)
      INSTALL_TAG="${2:-}"
      INSTALL_TRACK="tag"
      shift 2
      ;;
    --tag=*)
      INSTALL_TAG="${1#*=}"
      INSTALL_TRACK="tag"
      shift
      ;;
    --allow-unsigned-main)
      export MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN=1
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
      echo -e "${RED}Unknown argument: $1${NC}" >&2
      show_help
      exit 1
      ;;
  esac
done

[[ -n "$INSTALL_TAG" ]] && INSTALL_TRACK="tag"
INSTALL_TRACK="$(printf '%s' "$INSTALL_TRACK" | tr '[:upper:]' '[:lower:]')"
export MILLENNIUM_HELPERS_TRACK="$INSTALL_TRACK"
[[ -n "$INSTALL_TAG" ]] && export MILLENNIUM_HELPERS_TAG="$INSTALL_TAG"

check_root "$ACTION"

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}=== DRY RUN MODE: No changes will be made ===${NC}"
fi

install_completions() {
  # Clean up obsolete completions from older installations
  local obsolete_completions=("millennium-upgrade-stable" "millennium-upgrade-beta")
  local user_name="${SUDO_USER:-$(id -un)}"
  local USER_HOME
  USER_HOME="$(get_user_home "$user_name")"
  local user_nu_dir="${XDG_CONFIG_HOME:-${USER_HOME}/.config}/nushell/completions"

  local base_bash_dir="${MILLENNIUM_BASH_COMPLETION_DIR:-/usr/share/bash-completion/completions}"
  local base_zsh_dir="${MILLENNIUM_ZSH_COMPLETION_DIR:-/usr/share/zsh/site-functions}"
  local base_fish_dir="${MILLENNIUM_FISH_COMPLETION_DIR:-/usr/share/fish/vendor_completions.d}"
  local base_nu_dirs=("/usr/share/nushell/completions" "/usr/local/share/nushell/completions" "$user_nu_dir")

  if [[ "$(uname)" == "Darwin" ]]; then
    local brew_prefix="/opt/homebrew"
    if command -v brew &>/dev/null; then
      brew_prefix="$(brew --prefix)"
    fi
    base_bash_dir="${MILLENNIUM_BASH_COMPLETION_DIR:-${brew_prefix}/etc/bash_completion.d}"
    base_zsh_dir="${MILLENNIUM_ZSH_COMPLETION_DIR:-${brew_prefix}/share/zsh/site-functions}"
    base_fish_dir="${MILLENNIUM_FISH_COMPLETION_DIR:-${brew_prefix}/share/fish/vendor_completions.d}"
    base_nu_dirs=("${brew_prefix}/share/nushell/completions" "$user_nu_dir")
  fi

  if [[ -n "${MILLENNIUM_NUSHELL_COMPLETION_DIR:-}" ]]; then
    base_nu_dirs=("${MILLENNIUM_NUSHELL_COMPLETION_DIR}")
  fi

  for comp in "${obsolete_completions[@]}"; do
    local f="${base_bash_dir}/${comp}"
    if [[ -f "$f" && -w "$base_bash_dir" ]]; then
      execute rm -f "$f"
    fi
  done

  # Also clean up from local share directories
  for base_dir in "/usr/share" "/usr/local/share"; do
    local obsolete_zsh="${base_dir}/zsh/site-functions"
    for comp in "${obsolete_completions[@]}"; do
      local f="${obsolete_zsh}/_${comp}"
      if [[ -f "$f" && -w "$obsolete_zsh" ]]; then
        execute rm -f "$f"
      fi
    done
    local obsolete_fish="${base_dir}/fish/vendor_completions.d"
    for comp in "${obsolete_completions[@]}"; do
      local f="${obsolete_fish}/${comp}.fish"
      if [[ -f "$f" && -w "$obsolete_fish" ]]; then
        execute rm -f "$f"
      fi
    done
  done

  echo -e "${BLUE}Installing shell autocompletions...${NC}"

  # 1. Bash Completions
  if [[ -d "$base_bash_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Installing Bash completions... "
    if execute mkdir -p "$base_bash_dir" && \
       execute cp -f "${SCRIPT_DIR}/completions/bash/millennium-helpers" "$base_bash_dir/millennium-helpers" && \
       execute chmod 644 "$base_bash_dir/millennium-helpers" && \
       change_owner "$base_bash_dir/millennium-helpers"; then
      local symlinks_ok=true
      for item in "${SCRIPTS[@]}"; do
        local dest="${item#*:}"
        execute ln -sf "millennium-helpers" "${base_bash_dir}/${dest}" || symlinks_ok=false
      done
      if [[ "$symlinks_ok" == "true" ]]; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL (symlinks)${NC}"
        echo -e "${RED}Error: Failed to create symlinks for some Bash completion scripts in ${base_bash_dir}.${NC}" >&2
        exit 1
      fi
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to copy or configure Bash completion base script in ${base_bash_dir}.${NC}" >&2
      exit 1
    fi
  fi

  # 2. Zsh Completions
  if [[ -d "$base_zsh_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Installing Zsh completions... "
    if execute mkdir -p "$base_zsh_dir" && \
       execute cp -f "${SCRIPT_DIR}/completions/zsh/_millennium-helpers" "$base_zsh_dir/_millennium-helpers" && \
       execute chmod 644 "$base_zsh_dir/_millennium-helpers" && \
       change_owner "$base_zsh_dir/_millennium-helpers"; then
      local symlinks_ok=true
      for item in "${SCRIPTS[@]}"; do
        local dest="${item#*:}"
        execute ln -sf "_millennium-helpers" "${base_zsh_dir}/_${dest}" || symlinks_ok=false
      done
      if [[ "$symlinks_ok" == "true" ]]; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL (symlinks)${NC}"
        echo -e "${RED}Error: Failed to create symlinks for some Zsh completion scripts in ${base_zsh_dir}.${NC}" >&2
        exit 1
      fi
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to copy or configure Zsh completion base script in ${base_zsh_dir}.${NC}" >&2
      exit 1
    fi
  fi

  # 3. Fish Completions
  if [[ -d "$base_fish_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Installing Fish completions... "
    local fish_ok=true
    execute mkdir -p "$base_fish_dir" || fish_ok=false
    if [[ "$fish_ok" == "true" ]]; then
      for file in "${SCRIPT_DIR}/completions/fish/"*.fish; do
        [[ -f "$file" ]] || continue
        if ! (execute cp -f "$file" "$base_fish_dir/" && \
              execute chmod 644 "${base_fish_dir}/$(basename "$file")" && \
              change_owner "${base_fish_dir}/$(basename "$file")"); then
          fish_ok=false
        fi
      done
    fi
    if [[ "$fish_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to copy or configure Fish completions in ${base_fish_dir}.${NC}" >&2
      exit 1
    fi
  fi

  # 4. Nushell Completions
  for cand_dir in "${base_nu_dirs[@]}"; do
    local try_nu=false
    if [[ "$DRY_RUN" == "true" || "$cand_dir" == "$user_nu_dir" || -d "$cand_dir" ]]; then
      try_nu=true
    fi
    if [[ "$try_nu" != "true" ]]; then
      continue
    fi
    printf "Installing Nushell completions to %s... " "$cand_dir"
    if execute mkdir -p "$cand_dir" && \
       execute cp -f "${SCRIPT_DIR}/completions/nushell/millennium-helpers.nu" "$cand_dir/millennium-helpers.nu" && \
       execute chmod 644 "$cand_dir/millennium-helpers.nu" && \
       change_owner "$cand_dir/millennium-helpers.nu"; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to copy or configure Nushell completions in ${cand_dir}.${NC}" >&2
    fi
  done
}

install_man_pages() {
  local man_src="${SCRIPT_DIR}/man"
  if [[ ! -d "$man_src" ]]; then
    return 0
  fi

  local man_dir="${MILLENNIUM_MAN_DIR:-/usr/local/share/man/man1}"
  if [[ -n "${MILLENNIUM_MAN_DIR:-}" ]]; then
    :
  elif [[ "$(uname)" == "Darwin" ]]; then
    local brew_prefix="/opt/homebrew"
    if command -v brew &>/dev/null; then
      brew_prefix="$(brew --prefix)"
    fi
    man_dir="${brew_prefix}/share/man/man1"
  elif [[ -d "/usr/share/man/man1" && ! -d "/usr/local/share/man/man1" ]]; then
    # Prefer distro man path when /usr/local/share/man is unused
    man_dir="/usr/share/man/man1"
  fi

  echo -e "${BLUE}Installing man pages...${NC}"
  printf "Installing man pages to %s... " "$man_dir"
  if execute mkdir -p "$man_dir"; then
    local ok=true
    local page
    for page in "${man_src}"/*.1; do
      [[ -f "$page" ]] || continue
      local base
      base="$(basename "$page")"
      if ! execute cp -f "$page" "${man_dir}/${base}" || \
         ! execute chmod 644 "${man_dir}/${base}" || \
         ! change_owner "${man_dir}/${base}"; then
        ok=false
      fi
    done
    if [[ "$ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${YELLOW}Warning: Failed to install one or more man pages to ${man_dir}.${NC}" >&2
    fi
  else
    echo -e "${RED}FAIL${NC}"
    echo -e "${YELLOW}Warning: Could not create man page directory ${man_dir}.${NC}" >&2
  fi
}

uninstall_man_pages() {
  local man_dirs=("/usr/local/share/man/man1" "/usr/share/man/man1")
  if [[ -n "${MILLENNIUM_MAN_DIR:-}" ]]; then
    man_dirs=("${MILLENNIUM_MAN_DIR}")
  elif [[ "$(uname)" == "Darwin" ]]; then
    local brew_prefix="/opt/homebrew"
    if command -v brew &>/dev/null; then
      brew_prefix="$(brew --prefix)"
    fi
    man_dirs=("${brew_prefix}/share/man/man1")
  fi

  local pages=(
    millennium.1
    millennium-upgrade.1
    millennium-repair.1
    millennium-diag.1
    millennium-schedule.1
    millennium-purge.1
    millennium-theme.1
    millennium-mcp.1
  )

  echo -e "${BLUE}Uninstalling man pages...${NC}"
  for man_dir in "${man_dirs[@]}"; do
    [[ -d "$man_dir" || "$DRY_RUN" == "true" ]] || continue
    printf "Removing man pages from %s... " "$man_dir"
    local ok=true
    local page
    for page in "${pages[@]}"; do
      execute rm -f "${man_dir}/${page}" || ok=false
    done
    if [[ "$ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  done
}

run_wizard() {
  local user_name="${SUDO_USER:-$(id -un)}"
  local -a setup_args=()
  [[ "${DRY_RUN}" == "true" ]] && setup_args+=(--dry-run)

  # Normal installs skip the wizard when the effective user is root (no real
  # desktop user to configure). Tests and FORCE_WIZARD=true still run it.
  if [[ "$user_name" == "root" && "${FORCE_WIZARD:-}" != "true" ]]; then
    return 0
  fi

  # Setup wizard needs the Go dispatcher (even under dry-run).
  local go_bin="${SCRIPT_DIR}/bin/millennium"
  if [[ ! -x "$go_bin" ]] \
    && [[ -d "${SCRIPT_DIR}/go/cmd/millennium" ]] && command -v go >/dev/null 2>&1; then
    echo -e "${BLUE}Building Go dispatcher for setup wizard (bin/millennium)...${NC}"
    make -C "$SCRIPT_DIR" build >/dev/null || true
  fi

  if [[ -x "$go_bin" ]]; then
    if [[ "$user_name" != "root" && "$(id -u)" -eq 0 ]]; then
      runuser -l "$user_name" -c "FORCE_WIZARD=true MILLENNIUM_LEGACY=0 $(printf '%q' "$go_bin") schedule setup $(printf '%q ' "${setup_args[@]}")"
    else
      FORCE_WIZARD=true MILLENNIUM_LEGACY=0 "$go_bin" schedule setup "${setup_args[@]}"
    fi
    return $?
  fi

  echo -e "${YELLOW}Warning: Go dispatcher unavailable; skipping setup wizard.${NC}" >&2
  return 0
}

install_scripts() {
  local user_name="${SUDO_USER:-$(id -un)}"
  # Clean up obsolete script files from older installations
  local obsolete_scripts=("millennium-upgrade-stable" "millennium-upgrade-beta")
  for script in "${obsolete_scripts[@]}"; do
    local f="${TARGET_DIR}/${script}"
    if [[ -f "$f" && -w "$TARGET_DIR" ]]; then
      echo -e "${YELLOW}Removing obsolete script: ${f}${NC}"
      execute rm -f "$f"
    fi
  done

  echo -e "${BLUE}Installing Millennium helper tools to ${TARGET_DIR}...${NC}"

  for item in "${SCRIPTS[@]}"; do
    local src="${item%%:*}"
    local dest="${item#*:}"
    local src_path="${SCRIPT_DIR}/${src}"
    local dest_path="${TARGET_DIR}/${dest}"
    local kind="shell"

    if [[ "$dest" == "millennium" ]] || is_go_argv0_twin "$dest"; then
      if [[ "$dest" == "millennium" ]]; then
        DISPATCHER_SRC=""
        if ! resolve_millennium_dispatcher; then
          die_go_dispatcher_required
        fi
        src_path="${DISPATCHER_SRC}"
      else
        if ensure_go_dispatcher && [[ -x "${SCRIPT_DIR}/bin/millennium" || "${DRY_RUN:-false}" == "true" ]]; then
          src_path="${SCRIPT_DIR}/bin/millennium"
        else
          die_go_dispatcher_required
        fi
      fi
      kind="go"
      if [[ "${DRY_RUN:-false}" == "true" && ! -x "${SCRIPT_DIR}/bin/millennium" ]]; then
        printf "Installing: %s... " "$dest_path"
        echo -e "${YELLOW}[DRY RUN] Would install Go dispatcher as ${dest} (argv0 → command)${NC}"
        continue
      fi
      if [[ "$dest" == "millennium" ]]; then
        echo -e "${BLUE}Using Go dispatcher for PATH millennium${NC}"
      else
        echo -e "${BLUE}Using Go dispatcher for PATH ${dest} (argv0 twin)${NC}"
      fi
    fi

    if [[ ! -f "$src_path" && ! ( "$kind" == "go" && "${DRY_RUN:-false}" == "true" ) ]]; then
      echo -e "${RED}Error: Source script not found: ${src_path}${NC}" >&2
      exit 1
    fi

    # Copy binary/script, set ownership to root, and make executable (755)
    printf "Installing: %s... " "$dest_path"
    if execute cp -f "$src_path" "$dest_path" && \
       change_owner "$dest_path" && \
       execute chmod 755 "$dest_path"; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to install or configure helper ${dest_path}.${NC}" >&2
      echo -e "${YELLOW}Please ensure you have write permissions to ${TARGET_DIR} (you may need to run this script using sudo).${NC}" >&2
      exit 1
    fi
  done

  # Copy shared helper library and its modules
  local lib_dir="$LIB_DIR"
  printf "Installing shared helper library to %s... " "${lib_dir}/common.sh"
  if execute mkdir -p "${lib_dir}/lib" && \
     execute cp -f "${SCRIPT_DIR}/scripts/common.sh" "${lib_dir}/common.sh" && \
     execute cp -f "${SCRIPT_DIR}/scripts/lib/"*.sh "${lib_dir}/lib/" && \
     execute cp -f "${SCRIPT_DIR}/VERSION" "${lib_dir}/VERSION" && \
     { [[ -f "${SCRIPT_DIR}/third_party/MILLENNIUM-LICENSE.md" ]] && execute cp -f "${SCRIPT_DIR}/third_party/MILLENNIUM-LICENSE.md" "${lib_dir}/MILLENNIUM-LICENSE.md" || true; } && \
     change_owner -R "$lib_dir" && \
     execute chmod 755 "$lib_dir" && \
     execute chmod 755 "${lib_dir}/lib" && \
     execute chmod 644 "${lib_dir}/common.sh" && \
     execute chmod 644 "${lib_dir}/lib/"*.sh && \
     execute chmod 644 "${lib_dir}/VERSION" && \
     { [[ -f "${lib_dir}/MILLENNIUM-LICENSE.md" ]] && execute chmod 644 "${lib_dir}/MILLENNIUM-LICENSE.md" || true; }; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    echo -e "${RED}Error: Failed to copy or configure shared helper library directory ${lib_dir}.${NC}" >&2
    echo -e "${YELLOW}Please verify directory permissions for ${lib_dir}.${NC}" >&2
    exit 1
  fi

  # Record helpers install track (release|main|tag|checkout).
  if [[ "$DRY_RUN" == "false" ]] && declare -F write_helpers_install_meta >/dev/null 2>&1; then
    local meta_track="$INSTALL_TRACK" meta_ref="" meta_ver="" meta_url="${MILLENNIUM_HELPERS_SOURCE_URL:-}"
    meta_ver="$(tr -d '[:space:]' < "${lib_dir}/VERSION" 2>/dev/null || true)"
    # Local clone install without a piped source URL → checkout track.
    if [[ "$meta_track" == "release" && -z "$meta_url" && -d "${SCRIPT_DIR}/.git" ]]; then
      meta_track="checkout"
    fi
    case "$meta_track" in
      tag)
        meta_ref="$(helpers_normalize_tag "${INSTALL_TAG:-$meta_ver}" 2>/dev/null || printf 'v%s' "$meta_ver")"
        ;;
      main)
        meta_ref="$(helpers_fetch_main_commit_sha 2>/dev/null || true)"
        meta_ref="${meta_ref:-main}"
        ;;
      checkout)
        if [[ -d "${SCRIPT_DIR}/.git" ]]; then
          meta_ref="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo checkout)"
        else
          meta_ref="checkout"
        fi
        ;;
      *)
        meta_track="release"
        if [[ -n "$meta_ver" ]]; then
          meta_ref="v${meta_ver}"
        else
          meta_ref="latest"
        fi
        ;;
    esac
    write_helpers_install_meta "$lib_dir" "$meta_track" "$meta_ref" "$meta_ver" "$meta_url" "" || true
    change_owner "$(helpers_install_meta_path "$lib_dir")" 2>/dev/null || true
    execute chmod 644 "$(helpers_install_meta_path "$lib_dir")" 2>/dev/null || true
  fi

  install_completions
  install_man_pages

  # Configure passwordless sudoers rules in /etc/sudoers.d/millennium-helpers
  if [[ "$(uname)" != "Darwin" ]]; then
    if [[ "$user_name" != "root" ]]; then
      printf "Configuring passwordless sudo rule in %s... " "${SUDOERS_FILE}"

      local sudo_ok=true

      # Ensure target directory exists and has secure permissions
      local sudoers_d_dir
      sudoers_d_dir="$(dirname "$SUDOERS_FILE")"
      if [[ "$DRY_RUN" == "false" && ! -d "$sudoers_d_dir" ]]; then
        mkdir -p "$sudoers_d_dir" || sudo_ok=false
        chmod 750 "$sudoers_d_dir" || sudo_ok=false
        chown root:root "$sudoers_d_dir" || sudo_ok=false
      elif [[ "$DRY_RUN" == "true" ]]; then
        echo -e "\n${YELLOW}[DRY RUN] Would ensure directory exists with 750 permissions:${NC} ${sudoers_d_dir}"
      fi

      if [[ "$sudo_ok" == "true" ]]; then
        write_file "$SUDOERS_FILE" << EOF &>/dev/null || sudo_ok=false
# Automatically generated by Millennium helpers installer. Do not edit manually.
${user_name} ALL=(ALL) NOPASSWD: ${TARGET_DIR}/millennium upgrade, ${TARGET_DIR}/millennium upgrade *, ${TARGET_DIR}/millennium diag, ${TARGET_DIR}/millennium diag *, ${TARGET_DIR}/millennium repair, ${TARGET_DIR}/millennium repair *, ${TARGET_DIR}/millennium purge, ${TARGET_DIR}/millennium purge *, ${TARGET_DIR}/millennium-upgrade, ${TARGET_DIR}/millennium-diag, ${TARGET_DIR}/millennium-purge, ${TARGET_DIR}/millennium-repair
EOF

        execute chmod 440 "$SUDOERS_FILE" || sudo_ok=false
        execute chown root:root "$SUDOERS_FILE" || sudo_ok=false

        # Validate sudoers configuration with visudo
        if [[ "$DRY_RUN" == "false" ]]; then
          local visudo_err
          if visudo_err=$(visudo -cf "$SUDOERS_FILE" 2>&1); then
            if command -v restorecon &>/dev/null; then
              restorecon "$SUDOERS_FILE" || true
            fi
          elif [[ ! -t 0 && "${FORCE_RECOVERY:-}" != "true" ]]; then
            # Non-interactive terminal: log and fail
            echo -e "\n${RED}Error: visudo validation failed:${NC}" >&2
            echo "$visudo_err" >&2
            sudo_ok=false
            rm -f "$SUDOERS_FILE"
          else
            echo -e "\n${RED}Warning: visudo validation failed for the generated sudoers file:${NC}"
            echo -e "${visudo_err}"

            # Ask if they want to override the username or manually edit
            while true; do
              echo -e "\nWhat would you like to do?"
              echo -e "  1) Retry with a different user/group name"
              echo -e "  2) Skip sudoers configuration (continue installation without passwordless sudo)"
              echo -e "  3) Abort installation"
              read -rp "Selection [1-3, default: 3]: " choice_sel
              case "$choice_sel" in
                1)
                  local new_user=""
                  read -rp "Enter new user or group name (e.g. %wheel or custom_user): " new_user
                  if [[ -n "$new_user" ]]; then
                    # Rewrite file with new user
                    write_file "$SUDOERS_FILE" << EOF &>/dev/null
# Automatically generated by Millennium helpers installer. Do not edit manually.
${new_user} ALL=(ALL) NOPASSWD: ${TARGET_DIR}/millennium upgrade, ${TARGET_DIR}/millennium upgrade *, ${TARGET_DIR}/millennium diag, ${TARGET_DIR}/millennium diag *, ${TARGET_DIR}/millennium repair, ${TARGET_DIR}/millennium repair *, ${TARGET_DIR}/millennium purge, ${TARGET_DIR}/millennium purge *, ${TARGET_DIR}/millennium-upgrade, ${TARGET_DIR}/millennium-diag, ${TARGET_DIR}/millennium-purge, ${TARGET_DIR}/millennium-repair
EOF
                    chmod 440 "$SUDOERS_FILE"
                    chown root:root "$SUDOERS_FILE"
                    # Re-run validation
                    if visudo_err=$(visudo -cf "$SUDOERS_FILE" 2>&1); then
                      echo -e "${GREEN}Sudoers configuration validated successfully!${NC}"
                      if command -v restorecon &>/dev/null; then
                        restorecon "$SUDOERS_FILE" || true
                      fi
                      break
                    else
                      echo -e "${RED}visudo validation failed again:${NC}"
                      echo -e "${visudo_err}"
                    fi
                  fi
                  ;;
                2)
                  echo -e "${YELLOW}Skipping passwordless sudo setup. You will need to run helper scripts with root permissions manually.${NC}"
                  rm -f "$SUDOERS_FILE"
                  sudo_ok=true
                  break
                  ;;
                ""|3)
                  sudo_ok=false
                  rm -f "$SUDOERS_FILE"
                  break
                  ;;
                *)
                  echo -e "${RED}Invalid selection. Please choose 1, 2, or 3.${NC}"
                  ;;
              esac
            done
          fi
        fi
      fi

      if [[ "$sudo_ok" == "true" ]]; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL${NC}"
        echo -e "${RED}Error: Failed to configure or validate passwordless sudo rule in ${SUDOERS_FILE}.${NC}" >&2
        exit 1
      fi
    else
      echo -e "${YELLOW}Running as root directly. Skipping passwordless sudo configuration.${NC}"
    fi
  fi

  # Clean up legacy local user symlinks if they exist
  local user_home
  user_home="$(get_user_home "$user_name")"
  local user_bin="${user_home}/.local/bin"

  if [[ -d "$user_bin" || "$DRY_RUN" == "true" ]]; then
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      local legacy_path="${user_bin}/${dest}"
      if [[ -L "$legacy_path" || "$DRY_RUN" == "true" ]]; then
        echo "Removing legacy user symlink: $legacy_path"
        execute rm -f "$legacy_path"
      fi
    done
  fi



  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}Dry run completed successfully!${NC}"
  else
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "\n${BLUE}Getting started:${NC}"
    echo -e "  1. Check health:     ${GREEN}millennium diag${NC}"
    echo -e "  2. Install/update:   ${GREEN}millennium upgrade${NC}   (if Millennium is missing)"
    echo -e "  3. Review scheduler: ${GREEN}millennium schedule status${NC}"
    echo -e "  Tip: manage skins with ${GREEN}millennium theme list${NC}"
    if [[ -d "${user_home}/.var/app/com.valvesoftware.Steam" ]] || command -v flatpak &>/dev/null; then
      if flatpak info com.valvesoftware.Steam &>/dev/null 2>&1 || [[ -d "${user_home}/.var/app/com.valvesoftware.Steam" ]]; then
        echo -e "  Steam Deck / Flatpak: see docs/steam_deck.md"
      fi
    fi
    echo -e "\nInstalled commands:"
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      echo -e "  - ${dest}"
    done
    echo -e "  - millennium   (dispatcher: millennium diag|upgrade|doctor|...)"
    echo -e "\nLong names (millennium-diag, …) still work as aliases."
  fi
}

uninstall_completions() {
  local base_bash_dir="${MILLENNIUM_BASH_COMPLETION_DIR:-/usr/share/bash-completion/completions}"
  local base_zsh_dir="${MILLENNIUM_ZSH_COMPLETION_DIR:-/usr/share/zsh/site-functions}"
  local base_fish_dir="${MILLENNIUM_FISH_COMPLETION_DIR:-/usr/share/fish/vendor_completions.d}"
  local user_name="${SUDO_USER:-$(id -un)}"
  local USER_HOME
  USER_HOME="$(get_user_home "$user_name")"
  local user_nu_dir="${XDG_CONFIG_HOME:-${USER_HOME}/.config}/nushell/completions"
  local base_nu_dirs=("/usr/share/nushell/completions" "/usr/local/share/nushell/completions" "$user_nu_dir")

  if [[ "$(uname)" == "Darwin" ]]; then
    local brew_prefix="/opt/homebrew"
    if command -v brew &>/dev/null; then
      brew_prefix="$(brew --prefix)"
    fi
    base_bash_dir="${MILLENNIUM_BASH_COMPLETION_DIR:-${brew_prefix}/etc/bash_completion.d}"
    base_zsh_dir="${MILLENNIUM_ZSH_COMPLETION_DIR:-${brew_prefix}/share/zsh/site-functions}"
    base_fish_dir="${MILLENNIUM_FISH_COMPLETION_DIR:-${brew_prefix}/share/fish/vendor_completions.d}"
    base_nu_dirs=("${brew_prefix}/share/nushell/completions" "$user_nu_dir")
  fi

  if [[ -n "${MILLENNIUM_NUSHELL_COMPLETION_DIR:-}" ]]; then
    base_nu_dirs=("${MILLENNIUM_NUSHELL_COMPLETION_DIR}")
  fi

  echo -e "${BLUE}Uninstalling shell autocompletions...${NC}"

  # 1. Bash Completions
  if [[ -d "$base_bash_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing Bash completions... "
    local remove_ok=true
    execute rm -f "$base_bash_dir/millennium-helpers" || remove_ok=false
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      execute rm -f "${base_bash_dir}/${dest}" || remove_ok=false
    done
    if [[ "$remove_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  # 2. Zsh Completions
  if [[ -d "$base_zsh_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing Zsh completions... "
    local remove_ok=true
    execute rm -f "$base_zsh_dir/_millennium-helpers" || remove_ok=false
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      execute rm -f "${base_zsh_dir}/_${dest}" || remove_ok=false
    done
    if [[ "$remove_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  # 3. Fish Completions
  if [[ -d "$base_fish_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing Fish completions... "
    local remove_ok=true
    for item in "${SCRIPTS[@]}"; do
      local dest="${item#*:}"
      execute rm -f "${base_fish_dir}/${dest}.fish" || remove_ok=false
    done
    if [[ "$remove_ok" == "true" ]]; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAIL${NC}"
    fi
  fi

  # 4. Nushell Completions
  for cand_dir in "${base_nu_dirs[@]}"; do
    if [[ -d "$cand_dir" || -f "${cand_dir}/millennium-helpers.nu" || "$DRY_RUN" == "true" || "$cand_dir" == "$user_nu_dir" ]]; then
      printf "Removing Nushell completions from %s... " "$cand_dir"
      if execute rm -f "${cand_dir}/millennium-helpers.nu"; then
        echo -e "${GREEN}OK${NC}"
      else
        echo -e "${RED}FAIL${NC}"
      fi
    fi
  done
}

uninstall_scripts() {
  local purge_all=false
  if [[ "$PURGE_REQUESTED" == "true" ]]; then
    purge_all=true
  elif [[ -t 0 ]]; then
    # Print menu and read response if in interactive terminal
    echo -e "${YELLOW}Millennium Client Cleanup:${NC}"
    read -rp "Would you also like to completely purge all Millennium binaries, Steam hooks, and themes? [y/N]: " resp
    if [[ "$resp" =~ ^[Yy]$ ]]; then
      purge_all=true
    fi
  fi

  if [[ "$purge_all" == "true" ]]; then
    local purge_script="${SCRIPT_DIR}/scripts/millennium-purge.sh"
    if [[ -f "$purge_script" ]]; then
      echo -e "${YELLOW}Invoking Millennium purge script...${NC}"
      local dry_flag=""
      [[ "$DRY_RUN" == "true" ]] && dry_flag="--dry-run"
      # Already confirmed interactively (or via --purge); skip purge's own prompt.
      execute "$purge_script" --yes $dry_flag
    fi
  fi

  # Disable scheduler (systemd/LaunchAgent + cron) while binaries still exist.
  # Run as current euid (typically root under sudo) so system-scope units can
  # be removed; do not drop to runuser before disable.
  local user_name="${SUDO_USER:-$(id -un)}"
  local go_mill="${TARGET_DIR}/millennium"
  local schedule_bin="${TARGET_DIR}/millennium-schedule"
  local schedule_src="${SCRIPT_DIR}/scripts/millennium-schedule.sh"
  local schedule_cmd=""
  if [[ -x "$go_mill" ]]; then
    schedule_cmd="$go_mill schedule"
  elif [[ -x "$schedule_bin" ]]; then
    schedule_cmd="$schedule_bin"
  elif [[ -f "$schedule_src" ]]; then
    schedule_cmd="bash $schedule_src"
  fi
  if [[ -n "$schedule_cmd" || "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}Disabling update scheduler (systemd system+user / LaunchAgent and cron)...${NC}"
    local dry_flag=""
    [[ "$DRY_RUN" == "true" ]] && dry_flag="--dry-run"
    # shellcheck disable=SC2086
    execute ${schedule_cmd:-bash "$schedule_src"} disable $dry_flag || true
  fi

  echo -e "${BLUE}Uninstalling Millennium helper scripts from ${TARGET_DIR}...${NC}"

  local removed_any=false
  for item in "${SCRIPTS[@]}"; do
    local dest="${item#*:}"
    local dest_path="${TARGET_DIR}/${dest}"

    if [[ -f "$dest_path" || "$DRY_RUN" == "true" ]]; then
      printf "Removing: %s... " "$dest_path"
      if execute rm -f "$dest_path"; then
        echo -e "${GREEN}OK${NC}"
        removed_any=true
      else
        echo -e "${RED}FAIL${NC}"
        echo -e "${RED}Error: Failed to remove helper script ${dest_path}.${NC}" >&2
      fi
    fi
  done

  local lib_dir="$LIB_DIR"
  if [[ -d "$lib_dir" || "$DRY_RUN" == "true" ]]; then
    printf "Removing shared helper library: %s... " "${lib_dir}"
    if execute rm -rf "$lib_dir"; then
      echo -e "${GREEN}OK${NC}"
      removed_any=true
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to remove shared helper library directory ${lib_dir}.${NC}" >&2
    fi
  fi

  if [[ -f "$SUDOERS_FILE" || "$DRY_RUN" == "true" ]]; then
    printf "Removing: %s... " "$SUDOERS_FILE"
    if execute rm -f "$SUDOERS_FILE"; then
      echo -e "${GREEN}OK${NC}"
      removed_any=true
    else
      echo -e "${RED}FAIL${NC}"
      echo -e "${RED}Error: Failed to remove sudoers configuration file ${SUDOERS_FILE}.${NC}" >&2
    fi
  fi

  uninstall_completions
  uninstall_man_pages
  removed_any=true

  # Best-effort leftover unit cleanup if schedule disable could not run
  local system_systemd_dir="${MILLENNIUM_SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"
  local sys_timer="${system_systemd_dir}/millennium-update.timer"
  local sys_service="${system_systemd_dir}/millennium-update.service"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would remove leftover systemd system units under ${system_systemd_dir} (if present)${NC}"
    removed_any=true
  elif [[ -f "$sys_timer" || -f "$sys_service" ]]; then
    if [[ "$(id -u)" -eq 0 || -w "$system_systemd_dir" ]]; then
      echo "Removing leftover systemd system update timer/service..."
      execute systemctl disable --now millennium-update.timer || true
      execute systemctl stop millennium-update.service || true
      execute rm -f "$sys_timer" "$sys_service"
      execute systemctl daemon-reload || true
      removed_any=true
    fi
  fi

  if [[ "$user_name" != "root" ]]; then
    local user_home
    user_home="$(get_user_home "$user_name")"
    local user_xdg=""
    if [[ "$(id -u)" -eq 0 ]]; then
      # shellcheck disable=SC2016
      user_xdg=$(runuser -l "$user_name" -c 'echo "${XDG_CONFIG_HOME:-}"' 2>/dev/null || true)
    fi
    local user_systemd_dir
    if [[ -n "$user_xdg" ]]; then
      user_systemd_dir="${user_xdg}/systemd/user"
    else
      user_systemd_dir="${user_home}/.config/systemd/user"
    fi

    if [[ -d "$user_systemd_dir" || "$DRY_RUN" == "true" ]]; then
      local timer_file="${user_systemd_dir}/millennium-update.timer"
      local service_file="${user_systemd_dir}/millennium-update.service"

      if [[ -f "$timer_file" || -f "$service_file" ]]; then
        echo "Removing leftover systemd user update timer/service..."
        execute sysctl_user disable --now millennium-update.timer || true
        execute sysctl_user stop millennium-update.service || true
        execute rm -f "$timer_file" "$service_file"
        execute sysctl_user daemon-reload || true
        removed_any=true
      fi
    fi
  fi

  if [[ "$removed_any" == true || "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}Uninstallation completed successfully!${NC}"
  else
    echo -e "${YELLOW}No installed scripts or configuration found to uninstall.${NC}"
  fi
}

case "$ACTION" in
  install)
    if [[ ( ${#ORIGINAL_ARGS[@]} -eq 0 || "${FORCE_WIZARD:-}" == "true" ) && ( -t 0 || "${FORCE_WIZARD:-}" == "true" ) ]]; then
      run_wizard
    fi
    install_scripts
    ;;
  uninstall)
    uninstall_scripts
    ;;
esac
