# shellcheck shell=bash
# Logging and output helpers for Millennium Helpers.
# Sourced by common.sh

# Text color formatting (honors NO_COLOR / FORCE_COLOR / TTY)
# shellcheck disable=SC2034
if [[ -n "${NO_COLOR:-}" ]]; then
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
elif [[ -n "${FORCE_COLOR:-}" ]] || [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Quiet mode: suppress INFO (WARN/ERROR always print). Set via --quiet or MILLENNIUM_QUIET=1.
is_quiet() {
  # QUIET is exported so child helpers (and MILLENNIUM_QUIET) inherit quiet mode.
  [[ "${QUIET:-false}" == "true" || -n "${MILLENNIUM_QUIET:-}" ]]
}

# Suggest the closest known token for typos.
# Scoring (higher wins): 4 = prefix/extension, 3 = substring, else shared leading
# chars; subsequence matches (e.g. lst→list) score 3 minus length gap (floor 2).
# Returns nothing unless best_score >= 2 (avoids weak one-char coincidences).
# Usage: suggest_closest "lst" "list" "install" "update" "remove"
suggest_closest() {
  local input="$1"
  shift
  local c best="" best_score=0 score
  [[ -z "$input" ]] && return 0
  for c in "$@"; do
    score=0
    if [[ "$c" == "$input" ]]; then
      echo "$c"
      return 0
    fi
    if [[ "$c" == "$input"* || "$input" == "$c"* ]]; then
      score=4
    elif [[ "$c" == *"$input"* || "$input" == *"$c"* ]]; then
      score=3
    else
      # Count identical leading characters (e.g. "upg" vs "upgrade" → 3).
      local i=0
      while [[ $i -lt ${#c} && $i -lt ${#input} && "${c:$i:1}" == "${input:$i:1}" ]]; do
        i=$((i + 1))
      done
      score=$i
      # Subsequence: every input char appears in order in candidate (skip gaps).
      # Require len>=2 so a lone letter does not match every command.
      if [[ ${#input} -ge 2 ]]; then
        local ni=0 hi=0
        while [[ $ni -lt ${#input} && $hi -lt ${#c} ]]; do
          if [[ "${input:$ni:1}" == "${c:$hi:1}" ]]; then
            ni=$((ni + 1))
          fi
          hi=$((hi + 1))
        done
        if [[ $ni -eq ${#input} ]]; then
          # Prefer closer lengths: "lst"/"list" beats "lst"/"listall".
          local len_diff=$(( ${#c} - ${#input} ))
          [[ $len_diff -lt 0 ]] && len_diff=$(( -len_diff ))
          local sub_score=$((3 - len_diff))
          [[ $sub_score -lt 2 ]] && sub_score=2
          if [[ $sub_score -gt $score ]]; then
            score=$sub_score
          fi
        fi
      fi
    fi
    if [[ $score -gt $best_score ]]; then
      best_score=$score
      best=$c
    fi
  done
  if [[ $best_score -ge 2 && -n "$best" ]]; then
    echo "$best"
  fi
}

print_game_running_tip() {
  local action="${1:-continue}"
  echo -e "Close the running game, then re-run to ${action}. Use ${YELLOW}--yes${NC} to skip the Steam close prompt." >&2
}

log_msg() {
  local level="$1"
  local msg="$2"
  local timestamp
  timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  echo -e "[${timestamp}] [${level}] [$(basename "$0")] ${msg}"
}

log_info() {
  if is_quiet; then
    return 0
  fi
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

  if [[ ! -t 1 ]] || is_quiet; then
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

  # TTY: show curl's progress bar (bytes) instead of a spinner-only UX.
  # Progress goes to stderr; leave it on the TTY (do not redirect).
  printf "%s...\n" "$msg"
  local rc=0
  if ! curl -fL --progress-bar --retry 3 --retry-delay 2 ${headers[@]+"${headers[@]}"} "$url" -o "$dest"; then
    rc=$?
  fi

  if [[ $rc -eq 0 ]]; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAIL${NC}"
  fi
  rm -f "$tmp_log"
  return $rc
}

# Printed after upgrade failures so users know how to recover.
print_upgrade_failure_tips() {
  local exit_code="${1:-}"
  echo "" >&2
  if [[ -n "$exit_code" ]]; then
    echo -e "${RED}Upgrade failed (exit code: ${exit_code}).${NC}" >&2
  else
    echo -e "${RED}Upgrade failed.${NC}" >&2
  fi
  echo -e "Next steps:" >&2
  echo -e "  • ${YELLOW}millennium upgrade --rollback list${NC}   # list backups" >&2
  echo -e "  • ${YELLOW}millennium diag${NC}                     # check installation health" >&2
  echo -e "  • Re-run with ${YELLOW}--yes${NC} if Steam close confirmation blocked the update" >&2
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

# Run systemctl --user for the real target user, even when invoked via sudo.
# Under sudo, root has no $XDG_RUNTIME_DIR / session bus, so bare
# `systemctl --user` fails. Prefer systemd's --machine=user@.host syntax,
# then fall back to runuser with an explicit runtime dir.
#
# MILLENNIUM_USER_RUNTIME_ROOT overrides the /run/user prefix (tests only).
sysctl_user() {
  local target_user="${RUNNING_USER:-${SUDO_USER:-$(id -un)}}"

  if [[ "$(id -u)" -ne 0 || "$target_user" == "root" ]]; then
    systemctl --user "$@"
    return $?
  fi

  # Root → another user's systemd instance (supported path from systemd docs).
  local out rc=0
  out="$(systemctl --user -M "${target_user}@.host" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -eq 0 || ( "$out" != *"Failed to connect"* && "$out" != *"not defined"* && "$out" != *"Connection refused"* && "$out" != *"No such file"* ) ]]; then
    [[ -n "$out" ]] && printf '%s\n' "$out"
    return "$rc"
  fi

  local user_uid
  user_uid="$(id -u "$target_user" 2>/dev/null || true)"
  if [[ -z "$user_uid" ]]; then
    echo "Error: cannot resolve uid for user '${target_user}'." >&2
    return 1
  fi

  local runtime_root="${MILLENNIUM_USER_RUNTIME_ROOT:-/run/user}"
  local runtime_dir="${runtime_root}/${user_uid}"
  local bus_addr="unix:path=${runtime_dir}/bus"
  if [[ ! -S "${runtime_dir}/bus" && ! -d "$runtime_dir" ]]; then
    echo "Error: no user session for '${target_user}' (missing ${runtime_dir})." >&2
    echo "Log in as that user, or enable lingering: sudo loginctl enable-linger ${target_user}" >&2
    echo "Or re-run without sudo: millennium-schedule $*" >&2
    return 1
  fi

  if command -v runuser &>/dev/null; then
    runuser -u "$target_user" -- env \
      "XDG_RUNTIME_DIR=${runtime_dir}" \
      "DBUS_SESSION_BUS_ADDRESS=${bus_addr}" \
      systemctl --user "$@"
    return $?
  fi

  echo "Error: cannot talk to ${target_user}'s systemd user instance." >&2
  echo "$out" >&2
  return 1
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
