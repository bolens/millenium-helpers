#!/usr/bin/env bash
# Thin millennium-mcp entry when the Go dispatcher is not installed as this PATH name.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_millennium_go() {
  local cand
  for cand in \
    "${SCRIPT_DIR}/../bin/millennium" \
    "${SCRIPT_DIR}/millennium" \
    "$(command -v millennium 2>/dev/null || true)"
  do
    if [[ -n "$cand" && -x "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

if go_bin="$(resolve_millennium_go)"; then
  exec "$go_bin" mcp "$@"
fi

echo "Error: millennium MCP requires the Go millennium dispatcher (not found)." >&2
echo "Install millennium-helpers or run 'make build' from a checkout." >&2
exit 1
