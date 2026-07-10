# shellcheck shell=bash
# Helpers version resolution for Millennium Helpers.
# Sourced by common.sh

get_helpers_version() {
  local candidates=()
  local script_root
  script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null || true)"

  if [[ -n "$script_root" ]]; then
    candidates+=("${script_root}/VERSION")
  fi
  candidates+=(
    "${_COMMON_SCRIPT_DIR:-}/../VERSION"
    "${_COMMON_LIB_DIR:-}/../VERSION"
    "/usr/local/lib/millennium-helpers/VERSION"
    "/usr/lib/millennium-helpers/VERSION"
  )

  local path
  for path in "${candidates[@]}"; do
    [[ -n "$path" && -f "$path" ]] || continue
    local ver
    ver="$(tr -d '[:space:]' < "$path" 2>/dev/null || true)"
    if [[ -n "$ver" ]]; then
      echo "$ver"
      return 0
    fi
  done

  if command -v git >/dev/null 2>&1 && [[ -n "$script_root" && -d "${script_root}/.git" ]]; then
    local git_ver
    git_ver="$(git -C "$script_root" describe --tags --always --dirty 2>/dev/null || true)"
    if [[ -n "$git_ver" ]]; then
      echo "${git_ver#v}"
      return 0
    fi
  fi

  echo "unknown"
}

print_helpers_version() {
  local name
  name="$(basename "${0:-millennium-helpers}")"
  echo "${name} $(get_helpers_version)"
}
