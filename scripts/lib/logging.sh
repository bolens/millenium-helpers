# shellcheck shell=bash
# Logging and output helpers for Millennium Helpers.
# Sourced by common.sh

# Text color formatting
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[0;33m'
# shellcheck disable=SC2034
BLUE='\033[0;34m'
# shellcheck disable=SC2034
NC='\033[0m' # No Color

log_msg() {
  local level="$1"
  local msg="$2"
  local timestamp
  timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  echo -e "[${timestamp}] [${level}] [$(basename "$0")] ${msg}"
}

log_info() {
  log_msg "INFO" "$1"
}

log_warn() {
  log_msg "WARN" "$1"
}

log_error() {
  log_msg "ERROR" "$1" >&2
}

execute() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would run:${NC} $*"
  else
    "$@"
  fi
}

write_file() {
  local target="$1"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would write file: ${target} with contents:${NC}"
    cat
  else
    cat > "$target"
  fi
}

resolve_helper_path() {
  local name="$1"
  local found
  found=$(command -v "$name" 2>/dev/null || true)
  
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local local_sh="${script_dir}/${name}.sh"
  
  if [[ -f "$local_sh" ]]; then
    # Prefer local checkout if global command is missing or resolved to a standard system directory
    if [[ -z "$found" || "$found" == "/usr/bin/"* || "$found" == "/usr/local/bin/"* || "$found" == "/bin/"* ]]; then
      echo "$local_sh"
      return
    fi
  fi

  if [[ -n "$found" ]]; then
    echo "$found"
  else
    echo "/usr/local/bin/${name}"
  fi
}

download_file() {
  local url="$1"
  local dest="$2"
  local msg="${3:-Downloading}"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would download:${NC} ${url} -> ${dest}"
    return 0
  fi

  local headers=()
  if [[ -n "${GITHUB_TOKEN:-}" && "$url" == *"github.com"* ]]; then
    headers+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi

  local tmp_log
  tmp_log=$(mktemp 2>/dev/null || mktemp -t tmp.XXXXXX)
  
  if [[ ! -t 1 ]]; then
    printf "%s... " "$msg"
    if curl -fsSL --retry 3 --retry-delay 2 ${headers[@]+"${headers[@]}"} "$url" -o "$dest" >"$tmp_log" 2>&1; then
      echo -e "${GREEN}OK${NC}"
      rm -f "$tmp_log"
      return 0
    else
      echo -e "${RED}FAIL${NC}"
      cat "$tmp_log" >&2
      rm -f "$tmp_log"
      return 1
    fi
  fi

  curl -fsSL --retry 3 --retry-delay 2 ${headers[@]+"${headers[@]}"} "$url" -o "$dest" >"$tmp_log" 2>&1 &
  local pid=$!
  local spinner="/-\|"
  local i=0

  printf "%s...  " "$msg"
  while kill -0 "$pid" 2>/dev/null; do
    printf "\b%s" "${spinner:i++%4:1}"
    sleep 0.1
  done
  
  wait "$pid"
  local rc=$?
  
  printf "\b\b"
  if [[ $rc -eq 0 ]]; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    cat "$tmp_log" >&2
  fi
  rm -f "$tmp_log"
  return $rc
}

send_notification() {
  local title="$1"
  local msg="$2"
  local target_user="${3:-${SUDO_USER:-$(id -un)}}"
  
  if [[ "$target_user" != "root" ]] && command -v notify-send &>/dev/null; then
    local state_file
    state_file="$(relaunch_state_file "$target_user")"
    local env_prefix=""
    if _is_safe_relaunch_state_file "$target_user" "$state_file"; then
      local display_val wayland_val dbus_val runtime_val
      display_val=$(grep "^export DISPLAY=" "$state_file" | cut -d\' -f2 || true)
      wayland_val=$(grep "^export WAYLAND_DISPLAY=" "$state_file" | cut -d\' -f2 || true)
      dbus_val=$(grep "^export DBUS_SESSION_BUS_ADDRESS=" "$state_file" | cut -d\' -f2 || true)
      runtime_val=$(grep "^export XDG_RUNTIME_DIR=" "$state_file" | cut -d\' -f2 || true)
      
      [[ -n "$display_val" ]] && env_prefix+="DISPLAY=${display_val} "
      [[ -n "$wayland_val" ]] && env_prefix+="WAYLAND_DISPLAY=${wayland_val} "
      [[ -n "$dbus_val" ]] && env_prefix+="DBUS_SESSION_BUS_ADDRESS=${dbus_val} "
      [[ -n "$runtime_val" ]] && env_prefix+="XDG_RUNTIME_DIR=${runtime_val} "
    fi
    
    if [[ -z "$env_prefix" ]]; then
      local user_uid
      user_uid=$(id -u "$target_user" 2>/dev/null || true)
      if [[ -n "$user_uid" ]]; then
        env_prefix="DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${user_uid}/bus XDG_RUNTIME_DIR=/run/user/${user_uid} "
      else
        env_prefix="DISPLAY=:0 "
      fi
    fi
    
    runuser -l "$target_user" -c "${env_prefix}notify-send '${title}' '${msg}'" &>/dev/null || true
  fi
}

get_user_home() {
  local user="$1"
  local home=""
  if command -v getent &>/dev/null; then
    home="$(getent passwd "$user" | cut -d: -f6 || true)"
  fi
  if [[ -z "$home" ]] && command -v dscl &>/dev/null; then
    home="$(dscl . -read "/Users/${user}" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
  fi
  if [[ -z "$home" ]]; then
    home=$(eval echo "~${user}")
  fi
  echo "$home"
}

get_file_owner() {
  local file="$1"
  local os
  os=$(/usr/bin/uname 2>/dev/null || uname)
  if [[ "$os" == "Darwin" ]]; then
    stat -f '%Su' "$file" 2>/dev/null || echo ""
  else
    stat -c '%U' "$file" 2>/dev/null || echo ""
  fi
}

get_file_mtime() {
  local file="$1"
  local os
  os=$(/usr/bin/uname 2>/dev/null || uname)
  if [[ "$os" == "Darwin" ]]; then
    stat -f '%m' "$file" 2>/dev/null || echo 0
  else
    stat -c '%Y' "$file" 2>/dev/null || echo 0
  fi
}

get_file_size() {
  local file="$1"
  local os
  os=$(/usr/bin/uname 2>/dev/null || uname)
  if [[ "$os" == "Darwin" ]]; then
    stat -f '%z' "$file" 2>/dev/null || echo 0
  else
    stat -c '%s' "$file" 2>/dev/null || echo 0
  fi
}

get_file_perms() {
  local file="$1"
  local os
  os=$(/usr/bin/uname 2>/dev/null || uname)
  if [[ "$os" == "Darwin" ]]; then
    stat -f '%Lp' "$file" 2>/dev/null || echo ""
  else
    stat -c '%a' "$file" 2>/dev/null || echo ""
  fi
}

portable_realpath_m() {
  local target_path="$1"
  if [[ -e "$target_path" ]]; then
    realpath "$target_path" 2>/dev/null || python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$target_path"
  else
    local parent dir_base resolved_parent
    parent=$(dirname "$target_path")
    dir_base=$(basename "$target_path")
    resolved_parent=$(realpath "$parent" 2>/dev/null || python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$parent")
    echo "${resolved_parent}/${dir_base}"
  fi
}

