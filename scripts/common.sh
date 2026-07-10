#!/usr/bin/env bash
# Shared helper library entry point for Millennium Helpers.

# Normalize locale settings for invariant parsing and consistent outputs
if locale -a 2>/dev/null | grep -q "^C.UTF-8$"; then
  export LC_ALL=C.UTF-8
else
  export LC_ALL=C
fi

# Source modular components
_COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Support sourcing when installed under system directories, Homebrew prefix, or repo
_COMMON_LIB_DIR="${_COMMON_SCRIPT_DIR}/lib"
if [[ ! -d "$_COMMON_LIB_DIR" ]]; then
  for _lib_candidate in \
    "$(cd "${_COMMON_SCRIPT_DIR}/.." && pwd)/lib/millennium-helpers/lib" \
    "/usr/local/lib/millennium-helpers/lib" \
    "/usr/lib/millennium-helpers/lib"
  do
    if [[ -d "$_lib_candidate" ]]; then
      _COMMON_LIB_DIR="$_lib_candidate"
      break
    fi
  done
  unset _lib_candidate
fi

if [[ -f "${_COMMON_LIB_DIR}/logging.sh" ]]; then
  # shellcheck source=lib/logging.sh
  source "${_COMMON_LIB_DIR}/logging.sh"
else
  echo "Error: Shared logging library not found at ${_COMMON_LIB_DIR}/logging.sh" >&2
  exit 1
fi

if [[ -f "${_COMMON_LIB_DIR}/version.sh" ]]; then
  # shellcheck source=lib/version.sh
  source "${_COMMON_LIB_DIR}/version.sh"
fi

if [[ -f "${_COMMON_LIB_DIR}/github.sh" ]]; then
  # shellcheck source=lib/github.sh
  source "${_COMMON_LIB_DIR}/github.sh"
fi

if [[ -f "${_COMMON_LIB_DIR}/steam.sh" ]]; then
  # shellcheck source=lib/steam.sh
  source "${_COMMON_LIB_DIR}/steam.sh"
fi

if [[ -f "${_COMMON_LIB_DIR}/backup.sh" ]]; then
  # shellcheck source=lib/backup.sh
  source "${_COMMON_LIB_DIR}/backup.sh"
fi
