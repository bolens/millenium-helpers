#!/usr/bin/env bash
# Install official Millennium releases — thin-wrap to Go (Parallel peel).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH=""
for _common_candidate in \
  "${SCRIPT_DIR}/common.sh" \
  "$(cd "${SCRIPT_DIR}/.." && pwd)/lib/millennium-helpers/common.sh" \
  "/usr/local/lib/millennium-helpers/common.sh" \
  "/usr/lib/millennium-helpers/common.sh"
do
  if [[ -f "$_common_candidate" ]]; then
    COMMON_SH="$_common_candidate"
    break
  fi
done
unset _common_candidate
if [[ -f "$COMMON_SH" ]]; then
  # shellcheck disable=SC1090
  source "$COMMON_SH"
else
  echo -e "${RED:-}Error: Shared helper library not found." >&2
  exit 1
fi

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install official Millennium (stable, beta, or main) releases.

Options:
  -c, --channel CHANNEL  Update channel: stable, beta, or main
  --stable|--beta|--main
  -r, --rollback [ID]    Roll back (or pass "list")
  --file PATH            Install from a local archive
  --sha256 HEX           Expected SHA256 of --file
  --insecure-skip-verify Allow --file without checksum
  --all-users            Linux/macOS multi-user hooks
  -f, --force  -y, --yes  -d, --dry-run  -q, --quiet
  -V, --version  -h, --help
EOF
}

case "${1:-}" in
  -h|--help)
    show_help
    exit 0
    ;;
  -V|--version)
    print_helpers_version
    exit 0
    ;;
esac

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

if ! go_bin="$(resolve_millennium_go)"; then
  echo -e "${RED}Error: upgrade requires the Go millennium dispatcher (not found).${NC}" >&2
  echo "Install millennium-helpers or run 'make build' from a checkout." >&2
  exit 1
fi

MILLENNIUM_LEGACY=0 exec "$go_bin" upgrade "$@"
