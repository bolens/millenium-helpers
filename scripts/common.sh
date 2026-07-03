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
  tmp_log=$(mktemp)
  
  if [[ ! -t 1 ]]; then
    printf "%s... " "$msg"
    if curl -fsSL --retry 3 --retry-delay 2 "${headers[@]}" "$url" -o "$dest" >"$tmp_log" 2>&1; then
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

  curl -fsSL --retry 3 --retry-delay 2 "${headers[@]}" "$url" -o "$dest" >"$tmp_log" 2>&1 &
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
        print(f\"{d.get('github_token', '')}:{d.get('update_channel', '')}:{d.get('backup_limit', 5)}:{d.get('backup_max_age_days', '')}\")
except Exception:
    print(':::')
" 2>/dev/null || echo ":::")
    
    local config_token="${parsed%%:*}"
    local rest1="${parsed#*:}"
    local config_channel="${rest1%%:*}"
    local rest2="${rest1#*:}"
    local config_limit="${rest2%%:*}"
    local config_max_age="${rest2#*:}"
    
    if [[ -n "$config_token" && -z "${GITHUB_TOKEN:-}" ]]; then
      export GITHUB_TOKEN="$config_token"
    fi
    if [[ -n "$config_channel" && -z "${CONFIG_UPDATE_CHANNEL:-}" ]]; then
      export CONFIG_UPDATE_CHANNEL="$config_channel"
    fi
    if [[ -n "$config_limit" && -z "${CONFIG_BACKUP_LIMIT:-}" ]]; then
      export CONFIG_BACKUP_LIMIT="$config_limit"
    fi
    if [[ -n "$config_max_age" && -z "${CONFIG_BACKUP_MAX_AGE_DAYS:-}" ]]; then
      export CONFIG_BACKUP_MAX_AGE_DAYS="$config_max_age"
    fi
    export CONFIG_BACKUP_LIMIT="${CONFIG_BACKUP_LIMIT:-5}"
    export CONFIG_BACKUP_MAX_AGE_DAYS="${CONFIG_BACKUP_MAX_AGE_DAYS:-}"
  else
    export CONFIG_BACKUP_LIMIT="${CONFIG_BACKUP_LIMIT:-5}"
    export CONFIG_BACKUP_MAX_AGE_DAYS="${CONFIG_BACKUP_MAX_AGE_DAYS:-}"
  fi
}

load_user_config

prune_backups() {
  local max_keep="${1:-${CONFIG_BACKUP_LIMIT:-5}}"
  local age_days="${2:-${CONFIG_BACKUP_MAX_AGE_DAYS:-}}"
  local lib_dir="${MOCK_LIB_DIR:-/usr/lib}"

  local backups=()
  for d in "${lib_dir}"/millennium.bak_*; do
    if [[ -d "$d" ]]; then
      backups+=("$d")
    fi
  done

  if [[ -d "${lib_dir}/millennium.bak" ]]; then
    backups+=("${lib_dir}/millennium.bak")
  fi

  if [[ ${#backups[@]} -eq 0 ]]; then
    return 0
  fi

  local sorted_backups
  # shellcheck disable=SC2207
  sorted_backups=($(printf '%s\n' "${backups[@]}" | sort || true))
  local count=${#sorted_backups[@]}

  # 1. Prune by age if specified
  if [[ -n "$age_days" && "$age_days" =~ ^[0-9]+$ ]]; then
    local now_sec
    now_sec=$(date +%s)
    local limit_sec=$((now_sec - age_days * 86400))

    for b in "${sorted_backups[@]}"; do
      local mtime
      if mtime=$(stat -c %Y "$b" 2>/dev/null); then
        if [[ "$mtime" -lt "$limit_sec" ]]; then
          if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}[DRY RUN] Would delete old backup: ${b}${NC}"
          else
            execute rm -rf "$b"
            echo -e "Removed old backup: $(basename "$b")"
          fi
          # Remove from active list
          local temp_sorted=()
          for item in "${sorted_backups[@]}"; do
            [[ "$item" != "$b" ]] && temp_sorted+=("$item")
          done
          sorted_backups=("${temp_sorted[@]}")
        fi
      fi
    done
    count=${#sorted_backups[@]}
  fi

  # 2. Prune by count
  if [[ "$count" -gt "$max_keep" ]]; then
    local prune_count=$((count - max_keep))
    echo -e "${BLUE}Pruning oldest backups (keeping max ${max_keep})...${NC}"
    for ((i=0; i<prune_count; i++)); do
      local b="${sorted_backups[i]}"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Would prune backup: ${b}${NC}"
      else
        execute rm -rf "$b"
        echo -e "Pruned backup: $(basename "$b")"
      fi
    done
  fi
}

list_backups() {
  local lib_dir="${MOCK_LIB_DIR:-/usr/lib}"
  local backups=()
  for d in "${lib_dir}"/millennium.bak_*; do
    if [[ -d "$d" ]]; then
      backups+=("$(basename "$d")")
    fi
  done
  if [[ -d "${lib_dir}/millennium.bak" ]]; then
    backups+=("millennium.bak")
  fi
  if [[ ${#backups[@]} -gt 0 ]]; then
    printf '%s\n' "${backups[@]}" | sort || true
  fi
}

perform_rollback() {
  local target="${1:-}"
  local lib_dir="${MOCK_LIB_DIR:-/usr/lib}"
  local backups
  # shellcheck disable=SC2207
  backups=($(list_backups))
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No backups available to roll back to.${NC}" >&2
    exit 1
  fi
  
  if [[ -z "$target" ]]; then
    if [[ ${#backups[@]} -eq 1 ]]; then
      target="${backups[0]}"
    else
      if [[ ! -t 0 ]]; then
        target="${backups[-1]}"
      else
        echo -e "\n${BLUE}Available Backups:${NC}"
        for i in "${!backups[@]}"; do
          local label="${backups[i]#millennium.bak_}"
          [[ "$label" == "millennium.bak" ]] && label="Legacy Backup (millennium.bak)"
          echo -e "  $((i+1))) ${label}"
        done
        local sel=""
        while true; do
          read -rp "Select a backup to roll back to [1-${#backups[@]}]: " sel
          if [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le ${#backups[@]} ]]; then
            target="${backups[sel-1]}"
            break
          else
            echo -e "${RED}Invalid selection.${NC}"
          fi
        done
      fi
    fi
  elif [[ "$target" == "list" ]]; then
    echo -e "${BLUE}Available Backups:${NC}"
    for b in "${backups[@]}"; do
      local label="${b#millennium.bak_}"
      [[ "$label" == "millennium.bak" ]] && label="Legacy Backup (millennium.bak)"
      echo "  - ${label}"
    done
    exit 0
  else
    local found=""
    for b in "${backups[@]}"; do
      if [[ "$b" == "millennium.bak_${target}" || "$b" == "$target" ]]; then
        found="$b"
        break
      fi
    done
    if [[ -z "$found" ]]; then
      echo -e "${RED}Error: Backup '${target}' not found.${NC}" >&2
      exit 1
    fi
    target="$found"
  fi
  
  local backup_path="${lib_dir}/${target}"
  local dest_dir="${lib_dir}/millennium"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would swap active version with backup ${backup_path}${NC}"
  else
    local rollback_temp
    rollback_temp="${lib_dir}/millennium.rolled_back_$(date +%Y%m%d%H%M%S)"
    if [[ -d "$dest_dir" ]]; then
      execute mv "$dest_dir" "$rollback_temp"
    fi
    if execute mv "$backup_path" "$dest_dir"; then
      echo -e "${GREEN}Rollback successful! Backup ${target#millennium.bak_} is now active.${NC}"
      if [[ -d "$rollback_temp" ]]; then
        local old_ver="unknown"
        if [[ -f "$rollback_temp/version.txt" ]]; then
          old_ver=$(cat "$rollback_temp/version.txt" | tr -d '[:space:]')
        fi
        local moved_bak="${lib_dir}/millennium.bak_${old_ver}"
        execute rm -rf "$moved_bak"
        execute mv "$rollback_temp" "$moved_bak"
        echo -e "Saved rolled back version to $(basename "$moved_bak")"
      fi
    else
      echo -e "${RED}Error: Failed to swap backup.${NC}" >&2
      if [[ -d "$rollback_temp" ]]; then
        execute mv "$rollback_temp" "$dest_dir"
      fi
      exit 1
    fi
  fi
}

