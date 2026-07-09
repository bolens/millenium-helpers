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

# Support sourcing when installed under system directories or in repository
_COMMON_LIB_DIR="${_COMMON_SCRIPT_DIR}/lib"
if [[ ! -d "$_COMMON_LIB_DIR" ]]; then
  _COMMON_LIB_DIR="/usr/local/lib/millennium-helpers/lib"
  if [[ ! -d "$_COMMON_LIB_DIR" ]]; then
    _COMMON_LIB_DIR="/usr/lib/millennium-helpers/lib"
  fi
fi

if [[ -f "${_COMMON_LIB_DIR}/logging.sh" ]]; then
  # shellcheck source=lib/logging.sh
  source "${_COMMON_LIB_DIR}/logging.sh"
else
  echo "Error: Shared logging library not found at ${_COMMON_LIB_DIR}/logging.sh" >&2
  exit 1
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
