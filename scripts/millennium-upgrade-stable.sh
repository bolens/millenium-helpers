#!/usr/bin/env bash
# Wrapper script for millennium-upgrade stable updates
set -euo pipefail

UPGRADE_CMD="millennium-upgrade"
if ! command -v "$UPGRADE_CMD" &>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  UPGRADE_CMD="${SCRIPT_DIR}/millennium-upgrade.sh"
fi

exec "$UPGRADE_CMD" --channel stable "$@"
