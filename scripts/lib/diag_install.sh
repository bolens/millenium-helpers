# shellcheck shell=bash
# shellcheck disable=SC2034 # status globals read by millennium-diag.sh / doctor
# Install method detection and release tarball helpers
# --- Install method / release helpers ---------

HELPERS_REPO="${HELPERS_REPO:-bolens/millenium-helpers}"
INSTALL_METHOD=""
MIXED_INSTALL_OK=true
HELPERS_CHECKOUT=""
LATEST_RELEASE_TAG=""
LATEST_RELEASE_VERSION=""
DIAG_RELEASE_EXTRACT=""
DIAG_RELEASE_WORKDIR=""
HELPERS_TRACK=""
HELPERS_TRACK_REF=""
HELPERS_LIB_DIR=""

_diag_parse_json_field() {
  local json="$1"
  local field="$2"
  local parsed=""

  if command -v python3 &>/dev/null; then
    parsed=$(printf '%s' "$json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    val = data.get('${field}', '')
    if val is not None:
        print(val)
except Exception:
    pass
" 2>/dev/null || true)
  elif command -v jq &>/dev/null; then
    parsed=$(printf '%s' "$json" | jq -r ".${field} // empty" 2>/dev/null || true)
  else
    parsed=$(grep -m 1 "\"${field}\":" <<<"$json" | cut -d'"' -f4 || true)
  fi
  printf '%s' "$parsed"
}

_diag_helper_local_path() {
  local cmd_name="$1"
  if [[ -f "/usr/bin/${cmd_name}" ]]; then
    echo "/usr/bin/${cmd_name}"
  elif [[ -f "/usr/local/bin/${cmd_name}" ]]; then
    echo "/usr/local/bin/${cmd_name}"
  fi
}

_diag_file_sha256() {
  sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

_diag_cleanup_release_workdir() {
  if [[ -n "${DIAG_RELEASE_WORKDIR:-}" && -d "$DIAG_RELEASE_WORKDIR" ]]; then
    rm -rf "$DIAG_RELEASE_WORKDIR"
    DIAG_RELEASE_WORKDIR=""
  fi
}

find_helpers_checkout() {
  if [[ -n "${DIAG_TEST_CHECKOUT:-}" ]]; then
    HELPERS_CHECKOUT="$DIAG_TEST_CHECKOUT"
    return 0
  fi

  HELPERS_CHECKOUT=""
  local candidates=()
  local tail_root=""
  tail_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null || true)"
  [[ -n "$tail_root" ]] && candidates+=("$tail_root")
  candidates+=(
    "${HOME}/dev/millenium-helpers"
    "${HOME}/millenium-helpers"
    "${USER_HOME}/dev/millenium-helpers"
    "${USER_HOME}/millenium-helpers"
    "${USER_HOME}/src/millenium-helpers"
  )

  local dir
  for dir in "${candidates[@]}"; do
    [[ -n "$dir" ]] || continue
    if [[ -f "${dir}/packaging/millennium-helpers-git/PKGBUILD" ]] \
      || [[ -f "${dir}/packaging/millennium-helpers/PKGBUILD" ]]; then
      HELPERS_CHECKOUT="$dir"
      return 0
    fi
  done
  return 1
}

helpers_are_pacman_packaged() {
  if [[ "${DIAG_TEST_PACMAN_PACKAGED:-}" == "true" ]]; then
    return 0
  fi
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Qo /usr/bin/millennium >/dev/null 2>&1
}

helpers_are_pacman_git() {
  if [[ "${DIAG_TEST_PACMAN_GIT:-}" == "true" ]]; then
    return 0
  fi
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Q millennium-helpers-git &>/dev/null
}

_diag_helpers_lib_dir() {
  if [[ -n "${DIAG_TEST_LIB_DIR:-}" ]]; then
    echo "$DIAG_TEST_LIB_DIR"
    return 0
  fi
  if [[ -d /usr/local/lib/millennium-helpers ]]; then
    echo /usr/local/lib/millennium-helpers
  elif [[ -d /usr/lib/millennium-helpers ]]; then
    echo /usr/lib/millennium-helpers
  fi
}

# Load or migrate install-meta; sets HELPERS_TRACK / HELPERS_TRACK_REF.
ensure_helpers_track_meta() {
  HELPERS_LIB_DIR="$(_diag_helpers_lib_dir)"
  HELPERS_TRACK="${DIAG_TEST_HELPERS_TRACK:-}"
  HELPERS_TRACK_REF="${DIAG_TEST_HELPERS_REF:-}"

  if [[ -n "$HELPERS_TRACK" ]]; then
    return 0
  fi

  if [[ -n "$HELPERS_LIB_DIR" ]] && declare -F migrate_helpers_install_meta_if_needed >/dev/null 2>&1; then
    local method="manual"
    if helpers_are_pacman_git; then
      method="pacman-git"
    elif [[ "$INSTALL_METHOD" == "pacman" ]] || helpers_are_pacman_packaged; then
      method="pacman"
    elif [[ -n "${HELPERS_CHECKOUT:-}" ]]; then
      method="checkout"
    fi
    migrate_helpers_install_meta_if_needed "$HELPERS_LIB_DIR" "$method" "${HELPERS_CHECKOUT:-}" || true
  fi

  if [[ -n "$HELPERS_LIB_DIR" ]] && declare -F read_helpers_install_meta >/dev/null 2>&1; then
    if read_helpers_install_meta "$HELPERS_LIB_DIR"; then
      HELPERS_TRACK="${HELPERS_META_TRACK:-release}"
      HELPERS_TRACK_REF="${HELPERS_META_REF:-}"
      return 0
    fi
  fi

  if helpers_are_pacman_git; then
    HELPERS_TRACK="main"
    HELPERS_TRACK_REF="main"
  else
    HELPERS_TRACK="release"
    HELPERS_TRACK_REF="latest"
  fi
}

detect_install_method() {
  if [[ -n "${DIAG_TEST_INSTALL_METHOD:-}" ]]; then
    INSTALL_METHOD="$DIAG_TEST_INSTALL_METHOD"
    case "$INSTALL_METHOD" in
      mixed)
        MIXED_INSTALL_OK=false
        ;;
      *)
        MIXED_INSTALL_OK=true
        ;;
    esac
    if [[ -n "${DIAG_TEST_CHECKOUT:-}" ]]; then
      HELPERS_CHECKOUT="$DIAG_TEST_CHECKOUT"
    else
      find_helpers_checkout || true
    fi
    return 0
  fi

  local pacman_count=0
  local manual_count=0
  local missing_count=0
  local item cmd_name local_path

  for item in "${UTILITIES[@]}"; do
    cmd_name="${item%%:*}"
    local_path="$(_diag_helper_local_path "$cmd_name")"
    if [[ -z "$local_path" ]]; then
      missing_count=$((missing_count + 1))
      continue
    fi
    if command -v pacman >/dev/null 2>&1 && pacman -Qo "$local_path" >/dev/null 2>&1; then
      pacman_count=$((pacman_count + 1))
    else
      manual_count=$((manual_count + 1))
    fi
  done

  # Pacman under /usr/bin plus leftover install.sh copies under /usr/local.
  local local_leftover=false
  if [[ "$pacman_count" -gt 0 ]]; then
    local leftover
    for leftover in /usr/local/bin/millennium /usr/local/bin/millennium-*; do
      [[ -e "$leftover" || -L "$leftover" ]] || continue
      local_leftover=true
      break
    done
    if [[ -d /usr/local/lib/millennium-helpers ]]; then
      local_leftover=true
    fi
  fi

  if [[ "$pacman_count" -gt 0 && ( "$manual_count" -gt 0 || "$local_leftover" == "true" ) ]]; then
    INSTALL_METHOD="mixed"
    MIXED_INSTALL_OK=false
  elif [[ "$pacman_count" -gt 0 ]]; then
    INSTALL_METHOD="pacman"
    MIXED_INSTALL_OK=true
  elif [[ "$manual_count" -gt 0 ]]; then
    INSTALL_METHOD="manual"
    MIXED_INSTALL_OK=true
  else
    INSTALL_METHOD="none"
    MIXED_INSTALL_OK=true
  fi

  find_helpers_checkout || true
  ensure_helpers_track_meta || true
}

check_install_method() {
  detect_install_method
  echo -e "\nHelper Scripts Install Method:"

  case "$INSTALL_METHOD" in
    pacman)
      if helpers_are_pacman_git; then
        print_diag_item "ok" "Install method" "Pacman package (millennium-helpers-git)"
      else
        print_diag_item "ok" "Install method" "Pacman package (millennium-helpers)"
      fi
      ;;
    manual)
      print_diag_item "ok" "Install method" "Manual install (install.sh)"
      ;;
    mixed)
      print_diag_item "error" "Install method" "Mixed pacman and manual installs detected"
      ;;
    none)
      print_diag_item "warn" "Install method" "No helper scripts detected"
      ;;
    *)
      print_diag_item "warn" "Install method" "Unknown (${INSTALL_METHOD})"
      ;;
  esac

  if [[ -n "${HELPERS_TRACK:-}" ]]; then
    print_diag_item "ok" "Helpers track" "${HELPERS_TRACK}${HELPERS_TRACK_REF:+ (${HELPERS_TRACK_REF})}"
  fi

  if [[ -n "$HELPERS_CHECKOUT" ]]; then
    print_diag_item "ok" "Local packaging checkout" "${HELPERS_CHECKOUT}"
  fi
}

diag_completion_remote_for() {
  local want="$1"
  local i
  for i in "${!DIAG_COMPLETION_PATHS[@]}"; do
    if [[ "${DIAG_COMPLETION_PATHS[$i]}" == "$want" ]]; then
      echo "${DIAG_COMPLETION_REPOS[$i]}"
      return 0
    fi
  done
  return 1
}
