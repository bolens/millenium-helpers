#!/usr/bin/env bash
# Thin millennium-mcp entry when the Go dispatcher is not installed as this PATH name.
# Prefer: millennium mcp → Python millennium-mcp.py (escape hatch / legacy).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${MILLENNIUM_MCP_PYTHON:-}" != "1" && "${MILLENNIUM_LEGACY:-}" != "1" ]]; then
  if command -v millennium >/dev/null 2>&1; then
    exec millennium mcp "$@"
  fi
fi

PY_CANDIDATES=(
  "${SCRIPT_DIR}/millennium-mcp.py"
  "${SCRIPT_DIR}/../millennium-mcp.py"
  "/usr/lib/millennium-helpers/millennium-mcp.py"
)
for py in "${PY_CANDIDATES[@]}"; do
  if [[ -f "$py" ]]; then
    exec python3 "$py" "$@"
  fi
done

echo "Error: millennium-mcp.py not found; install millennium-helpers or set PATH." >&2
exit 1
