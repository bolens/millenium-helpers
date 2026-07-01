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
  if [[ -f "/usr/bin/${name}" ]]; then
    echo "/usr/bin/${name}"
  else
    echo "/usr/local/bin/${name}"
  fi
}

is_game_running() {
  local game_running=false
  for environ_file in /proc/[0-9]*/environ; do
    [[ -f "$environ_file" && -r "$environ_file" ]] || continue
    local pid_dir
    pid_dir="$(dirname "$environ_file")"
    local pid="${pid_dir##*/}"
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    
    local comm
    comm=$(cat "/proc/${pid}/comm" 2>/dev/null || true)
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
  local state_file="$2"
  
  local was_flatpak=false
  if command -v flatpak &>/dev/null && flatpak ps 2>/dev/null | grep -q "com.valvesoftware.Steam"; then
    was_flatpak=true
  fi
  
  local steam_pid
  steam_pid=$(pgrep -x steam | head -n 1 || true)
  
  mkdir -p "$(dirname "$state_file")"
  rm -f "$state_file"
  
  if [[ -n "$steam_pid" ]]; then
    local steam_env
    steam_env=$(tr '\0' '\n' < "/proc/${steam_pid}/environ" 2>/dev/null || true)
    
    local val
    for var in DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_CURRENT_DESKTOP; do
      val=$(echo "$steam_env" | grep "^${var}=" | cut -d= -f2- | head -n 1 || true)
      if [[ -n "$val" ]]; then
        echo "export ${var}='${val}'" >> "$state_file"
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
    
    echo "export STEAM_ARGS=\"${steam_args}\"" >> "$state_file"
    echo "export WAS_FLATPAK='${was_flatpak}'" >> "$state_file"
  else
    echo "export WAS_FLATPAK='${was_flatpak}'" >> "$state_file"
  fi
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
  local target_user="${3:-${SUDO_USER:-$USER}}"
  
  if [[ "$target_user" != "root" ]] && command -v notify-send &>/dev/null; then
    local state_file="/tmp/millennium-relaunch-${target_user}"
    local env_prefix=""
    if [[ -f "$state_file" ]]; then
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
