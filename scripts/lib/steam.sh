# shellcheck shell=bash
# Steam client management helpers for Millennium Helpers.
# Sourced by common.sh

relaunch_state_file() {
  local target_user="$1"
  local target_home
  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  if [[ -z "$target_home" ]]; then
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
  user_home="$(get_user_home "$target_user")"
  local state_file
  state_file="$(relaunch_state_file "$target_user")"

  if ! _is_safe_relaunch_state_file "$target_user" "$state_file"; then
    return 0
  fi

  echo "Relaunching Steam..."
  # shellcheck disable=SC1090
  source "$state_file"
  rm -f "$state_file"

  if [[ "$(uname)" == "Darwin" ]]; then
    if [[ "$(id -un)" == "$target_user" ]]; then
      open -a Steam >/dev/null 2>&1 &
    else
      runuser -l "$target_user" -c "open -a Steam >/dev/null 2>&1 &"
    fi
  elif [[ "${WAS_FLATPAK:-false}" == "true" ]]; then
    runuser "$target_user" -c "flatpak run com.valvesoftware.Steam ${STEAM_ARGS:-} >/dev/null 2>&1 &"
  else
    if command -v steam &>/dev/null; then
      runuser "$target_user" -c "steam ${STEAM_ARGS:-} >/dev/null 2>&1 &"
    elif [[ -x "${user_home}/.local/bin/steam" ]]; then
      runuser "$target_user" -c "${user_home}/.local/bin/steam ${STEAM_ARGS:-} >/dev/null 2>&1 &"
    fi
  fi
  return 0
}

is_game_running() {
  local game_running=false
  if [[ "$(uname)" == "Darwin" ]]; then
    # shellcheck disable=SC2009
    if ps -A -o command 2>/dev/null | grep -v "grep" | grep -q "steamapps/common"; then
      game_running=true
    fi
    [[ "$game_running" == "true" ]]
    return
  fi
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

  if [[ "$(uname)" == "Darwin" ]]; then
    echo "export WAS_MACOS='true'" > "$state_file"
    if [[ "$(id -u)" -eq 0 && "$(id -un)" != "$target_user" ]]; then
      chown "$target_user":"$target_user" "$state_file"
    fi
    return 0
  fi

  local was_flatpak=false
  if command -v flatpak &>/dev/null && flatpak ps 2>/dev/null | grep -q "com.valvesoftware.Steam"; then
    was_flatpak=true
  fi
  
  local steam_pid
  steam_pid=$(pgrep -x steam | head -n 1 || true)

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
  user_home="$(get_user_home "$target_user")"
  
  if [[ "$(uname)" == "Darwin" ]]; then
    if [[ "$(id -un)" == "$target_user" ]]; then
      osascript -e 'quit app "Steam"' || true
    else
      runuser -l "$target_user" -c "osascript -e 'quit app \"Steam\"'" || true
    fi
    
    local timeout=30
    while pgrep -ix Steam >/dev/null && [[ $timeout -gt 0 ]]; do
      sleep 1
      ((timeout--))
    done
    
    if pgrep -ix Steam >/dev/null; then
      echo "Steam did not close gracefully. Force killing..." >&2
      killall -9 Steam 2>/dev/null || true
    fi
    echo "Steam closed successfully."
    return 0
  fi

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
