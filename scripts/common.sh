#!/usr/bin/env bash
# Shared helper functions for the Millennium Helpers suite.

# shellcheck disable=SC2034
# Text color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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
  if [[ -n "$found" ]]; then
    echo "$found"
  else
    echo "/usr/local/bin/${name}"
  fi
}

_github_curl_headers() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "-H" "Authorization: token $GITHUB_TOKEN"
  fi
}

fetch_github_commit() {
  local owner="$1"
  local repo="$2"
  local headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi

  if command -v jq &>/dev/null; then
    curl -fsSL --retry 3 --retry-delay 2 "${headers[@]}" \
      "https://api.github.com/repos/${owner}/${repo}/commits" | jq -r '.[0].sha' || true
  else
    python3 -c "
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
" || true
  fi
}

fetch_github_latest_stable_tag() {
  local owner="$1"
  local repo="$2"
  local headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi

  if command -v jq &>/dev/null; then
    curl -sL --retry 3 --retry-delay 2 "${headers[@]}" \
      "https://api.github.com/repos/${owner}/${repo}/releases/latest" | jq -r '.tag_name' || true
  else
    python3 -c "
import urllib.request, json, os
try:
    headers = {'User-Agent': 'Mozilla/5.0'}
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization'] = f'token {token}'
    req = urllib.request.Request('https://api.github.com/repos/${owner}/${repo}/releases/latest', headers=headers)
    with urllib.request.urlopen(req) as response:
        print(json.loads(response.read().decode()).get('tag_name', ''))
except Exception:
    pass
" || true
  fi
}

fetch_github_latest_beta_tag() {
  local owner="$1"
  local repo="$2"
  local headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi

  if command -v jq &>/dev/null; then
    curl -sL --retry 3 --retry-delay 2 "${headers[@]}" \
      "https://api.github.com/repos/${owner}/${repo}/releases" \
      | jq -r '.[] | select(.prerelease == true and (.tag_name | contains("beta"))) | .tag_name' \
      | head -n 1 || true
  else
    python3 -c "
import urllib.request, json, os
try:
    headers = {'User-Agent': 'Mozilla/5.0'}
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization'] = f'token {token}'
    req = urllib.request.Request('https://api.github.com/repos/${owner}/${repo}/releases', headers=headers)
    with urllib.request.urlopen(req) as response:
        releases = json.loads(response.read().decode())
        for r in releases:
            if r.get('prerelease') and 'beta' in r.get('tag_name', ''):
                print(r['tag_name'])
                break
except Exception:
    pass
" || true
  fi
}

# Computes a safe, per-user path for the temporary steam-relaunch state
# file. This intentionally avoids world-writable /tmp: the file is written
# and later `source`d (potentially while running as root on behalf of
# another user), so placing it under a private, per-user directory prevents
# other local users from pre-planting a symlink at a predictable path
# (a classic /tmp TOCTOU privilege-escalation vector).
relaunch_state_file() {
  local target_user="$1"
  local target_home
  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  if [[ -z "$target_home" ]]; then
    # Should not happen in practice (caller already validated the user
    # exists), but fail safe rather than falling back to /tmp.
    echo ""
    return 1
  fi

  local state_dir
  if [[ "$(id -un)" == "$target_user" && -n "${XDG_STATE_HOME:-}" ]]; then
    state_dir="${XDG_STATE_HOME}/millennium-helpers"
  else
    state_dir="${target_home}/.local/state/millennium-helpers"
  fi
  echo "${state_dir}/relaunch.env"
}

# Creates (or re-secures) the directory that will hold the relaunch state
# file, ensuring it is owned by the target user and not group/world
# writable, so other local users cannot plant a symlink inside it.
_prepare_relaunch_state_dir() {
  local target_user="$1"
  local state_file="$2"
  local state_dir
  state_dir="$(dirname "$state_file")"
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
  if [[ "$(id -u)" -eq 0 && "$(id -un)" != "$target_user" ]]; then
    chown "$target_user":"$target_user" "$state_dir"
  fi
}

# Validates that a relaunch state file is safe to source: it must exist,
# must not be a symlink (never follow one, in case an attacker won a race
# before the directory was locked down), and must be owned by the target
# user (or root).
_is_safe_relaunch_state_file() {
  local target_user="$1"
  local state_file="$2"
  [[ -n "$state_file" ]] || return 1
  [[ -e "$state_file" ]] || return 1
  [[ -L "$state_file" ]] && return 1
  [[ -f "$state_file" ]] || return 1
  local owner
  owner="$(stat -c '%U' "$state_file" 2>/dev/null || true)"
  [[ -z "$owner" || "$owner" == "$target_user" || "$owner" == "root" ]]
}

relaunch_steam() {
  local target_user="$1"
  local user_home
  user_home="$(getent passwd "$target_user" | cut -d: -f6)"
  local state_file
  state_file="$(relaunch_state_file "$target_user")"

  if ! _is_safe_relaunch_state_file "$target_user" "$state_file"; then
    return 0
  fi

  echo "Relaunching Steam..."
  # shellcheck disable=SC1090
  source "$state_file"
  rm -f "$state_file"

  if [[ "${WAS_FLATPAK:-false}" == "true" ]]; then
    # shellcheck disable=SC2086
    runuser "$target_user" -c "flatpak run com.valvesoftware.Steam ${STEAM_ARGS:-} >/dev/null 2>&1 &"
  else
    if command -v steam &>/dev/null; then
      # shellcheck disable=SC2086
      runuser "$target_user" -c "steam ${STEAM_ARGS:-} >/dev/null 2>&1 &"
    elif [[ -x "${user_home}/.local/bin/steam" ]]; then
      # shellcheck disable=SC2086
      runuser "$target_user" -c "${user_home}/.local/bin/steam ${STEAM_ARGS:-} >/dev/null 2>&1 &"
    fi
  fi
}

is_game_running() {
  local game_running=false
  local proc_dir="${MOCK_PROC:-/proc}"
  for environ_file in "${proc_dir}"/[0-9]*/environ; do
    [[ -f "$environ_file" && -r "$environ_file" ]] || continue
    local pid_dir
    pid_dir="$(dirname "$environ_file")"
    local pid="${pid_dir##*/}"
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    
    local comm
    comm=$(cat "${proc_dir}/${pid}/comm" 2>/dev/null || true)
    [[ "$comm" == "steam" || "$comm" == "steamwebhelper" ]] && continue
    
    if { tr '\0' '\n' < "$environ_file"; } 2>/dev/null | grep -q "^SteamAppId=[1-9]"; then
      game_running=true
      break
    fi
  done
  [[ "$game_running" == "true" ]]
}

capture_steam_env() {
  local target_user="$1"
  local state_file
  state_file="$(relaunch_state_file "$target_user")"
  _prepare_relaunch_state_dir "$target_user" "$state_file"

  local was_flatpak=false
  if command -v flatpak &>/dev/null && flatpak ps 2>/dev/null | grep -q "com.valvesoftware.Steam"; then
    was_flatpak=true
  fi
  
  local steam_pid
  steam_pid=$(pgrep -x steam | head -n 1 || true)

  # Write to a fresh temp file in the same (now-locked-down) directory and
  # atomically rename it into place, rather than rm+append into the final
  # path. rename(2) replaces the destination path itself without following
  # a symlink there, closing the /tmp-style TOCTOU window this file used to
  # be exposed to.
  local tmp_file
  tmp_file="$(mktemp "${state_file}.XXXXXX")"
  chmod 600 "$tmp_file"
  
  if [[ -n "$steam_pid" ]]; then
    local steam_env
    steam_env=$(tr '\0' '\n' < "/proc/${steam_pid}/environ" 2>/dev/null || true)
    
    local val
    for var in DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_CURRENT_DESKTOP; do
      val=$(echo "$steam_env" | grep "^${var}=" | cut -d= -f2- | head -n 1 || true)
      if [[ -n "$val" ]]; then
        echo "export ${var}='${val}'" >> "$tmp_file"
      fi
    done
    
    local steam_args
    steam_args=$(python3 -c "
import sys
try:
    with open('/proc/' + sys.argv[1] + '/cmdline', 'rb') as f:
        args = f.read().split(b'\x00')
        args = [a.decode('utf-8', errors='ignore') for a in args if a][1:]
        print(' '.join(\"'\" + a.replace(\"'\", \"'\\\\''\") + \"'\" for a in args))
except Exception:
    pass
" "$steam_pid" 2>/dev/null || true)
    
    echo "export STEAM_ARGS=\"${steam_args}\"" >> "$tmp_file"
    echo "export WAS_FLATPAK='${was_flatpak}'" >> "$tmp_file"
  else
    echo "export WAS_FLATPAK='${was_flatpak}'" >> "$tmp_file"
  fi

  if [[ "$(id -u)" -eq 0 && "$(id -un)" != "$target_user" ]]; then
    chown "$target_user":"$target_user" "$tmp_file"
  fi
  mv -f "$tmp_file" "$state_file"
}

close_steam_gracefully() {
  local target_user="$1"
  local user_home
  user_home="$(getent passwd "$target_user" | cut -d: -f6)"
  
  local was_flatpak=false
  if command -v flatpak &>/dev/null && runuser -l "$target_user" -c "flatpak ps" 2>/dev/null | grep -q "com.valvesoftware.Steam"; then
    was_flatpak=true
  fi
  
  if [[ "$was_flatpak" == "true" ]]; then
    runuser -l "$target_user" -c "flatpak run com.valvesoftware.Steam -shutdown" || true
  elif command -v steam &>/dev/null; then
    runuser -l "$target_user" -c "steam -shutdown" || true
  elif [[ -x "${user_home}/.local/bin/steam" ]]; then
    runuser -l "$target_user" -c "${user_home}/.local/bin/steam -shutdown" || true
  fi

  local timeout=30
  while pgrep -x steam >/dev/null && [[ $timeout -gt 0 ]]; do
    sleep 1
    ((timeout--))
  done

  if pgrep -x steam >/dev/null; then
    echo "Steam did not close gracefully. Force killing..." >&2
    killall -9 steam steamwebhelper 2>/dev/null || true
  fi
  echo "Steam closed successfully."
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

load_user_config() {
  local user_name="${SUDO_USER:-$(id -un)}"
  local user_home
  user_home="$(getent passwd "$user_name" | cut -d: -f6 || echo "")"
  if [[ -z "$user_home" ]]; then
    user_home="$HOME"
  fi
  
  local config_dir="${XDG_CONFIG_HOME:-$user_home/.config}/millennium-helpers"
  local config_file="${config_dir}/config.json"
  
  if [[ -f "$config_file" ]]; then
    local parsed
    parsed=$(python3 -c "
import json, sys
try:
    with open('$config_file') as f:
        d = json.load(f)
        print(f\"{d.get('github_token', '')}:{d.get('update_channel', '')}\")
except Exception:
    print(':')
" 2>/dev/null || echo ":")
    
    local config_token="${parsed%%:*}"
    local config_channel="${parsed#*:}"
    
    if [[ -n "$config_token" && -z "${GITHUB_TOKEN:-}" ]]; then
      export GITHUB_TOKEN="$config_token"
    fi
    if [[ -n "$config_channel" && -z "${CONFIG_UPDATE_CHANNEL:-}" ]]; then
      export CONFIG_UPDATE_CHANNEL="$config_channel"
    fi
  fi
}

load_user_config

