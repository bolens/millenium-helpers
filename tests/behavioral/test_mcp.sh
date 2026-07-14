#!/usr/bin/env bash
# Behavioral tests for millennium MCP (Python façade + Go native server).
#
# MCP_IMPL=python|go|both (default: both). Protocol/tool-dispatch cases run
# per implementation. Python-only coverage: --register, TypedDicts, import seams.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

MCP_PY="${REPO_ROOT}/scripts/millennium-mcp.py"
GO_BIN="${GO_BIN:-${REPO_ROOT}/bin/millennium}"
MCP_IMPL="${MCP_IMPL:-both}"

setup_mock_bin
# Go dispatcher stub: Phase 5a prefers `millennium <feature>` for tools;
# Phase 5c native server uses self-exec for the same argv shape.
mock_cmd "millennium" "exit 0"
mock_cmd "millennium-diag" "exit 0"
mock_cmd "millennium-theme" "exit 0"
mock_cmd "millennium-upgrade" "exit 0"
mock_cmd "millennium-schedule" "exit 0"
mock_cmd "millennium-repair" "exit 0"
mock_cmd "millennium-purge" "exit 0"
trap teardown_mock_bin EXIT

ensure_go_bin() {
  if [[ -x "${GO_BIN}" ]]; then
    return 0
  fi
  echo "Building Go binary for MCP_IMPL=go/both…"
  make -C "${REPO_ROOT}" build
  [[ -x "${GO_BIN}" ]] || {
    echo "error: expected ${GO_BIN} after make build" >&2
    exit 1
  }
}

IMPLS=()
case "${MCP_IMPL}" in
  python) IMPLS=(python) ;;
  go)
    ensure_go_bin
    IMPLS=(go)
    ;;
  both)
    ensure_go_bin
    IMPLS=(python go)
    ;;
  *)
    echo "error: MCP_IMPL must be python, go, or both (got ${MCP_IMPL})" >&2
    exit 1
    ;;
esac

echo -e "${YELLOW}=== Behavioral tests: millennium MCP (impl=${MCP_IMPL}) ===${NC}"

# Sends one or more JSON-RPC request lines to the server over stdin and
# returns all stdout response lines.
run_mcp() {
  case "${MCP_IMPL_ACTIVE}" in
    python)
      printf '%s\n' "$@" | MILLENNIUM_MCP_PYTHON=1 python3 "$MCP_PY" 2>/dev/null
      ;;
    go)
      printf '%s\n' "$@" | "$GO_BIN" mcp 2>/dev/null
      ;;
    *)
      echo "error: MCP_IMPL_ACTIVE unset" >&2
      return 1
      ;;
  esac
}

# Same as run_mcp() but returns stderr (where run_cmd logs production argv).
run_mcp_stderr() {
  case "${MCP_IMPL_ACTIVE}" in
    python)
      { printf '%s\n' "$@" | MILLENNIUM_MCP_PYTHON=1 python3 "$MCP_PY" >/dev/null; } 2>&1
      ;;
    go)
      { printf '%s\n' "$@" | "$GO_BIN" mcp >/dev/null; } 2>&1
      ;;
    *)
      echo "error: MCP_IMPL_ACTIVE unset" >&2
      return 1
      ;;
  esac
}

run_protocol_suite() {
  local tag="[${MCP_IMPL_ACTIVE}]"

  # --- initialize ---

  resp=$(run_mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
  assert_valid_json "$resp" "${tag} initialize response is valid JSON"
  assert_contains "$resp" '"protocolVersion"' "${tag} initialize response includes a protocolVersion"
  assert_contains "$resp" '"id": 1' "${tag} initialize response echoes the request id"

  # --- tools/list ---

  resp=$(run_mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')
  assert_valid_json "$resp" "${tag} tools/list response is valid JSON"
  for tool in millennium_diag millennium_theme millennium_upgrade millennium_schedule millennium_repair millennium_purge; do
    assert_contains "$resp" "\"${tool}\"" "${tag} tools/list includes the ${tool} tool"
  done
  assert_contains "$resp" '"confirm"' "${tag} tools/list millennium_purge schema includes confirm"
  assert_contains "$resp" '"dry_run"' "${tag} tools/list millennium_purge schema includes dry_run"

  # --- unknown method ---

  resp=$(run_mcp '{"jsonrpc":"2.0","id":3,"method":"not/a/real/method","params":{}}')
  assert_contains "$resp" '"error"' "${tag} an unrecognized method returns a JSON-RPC error"
  assert_contains "$resp" '-32601' "${tag} unrecognized method returns JSON-RPC 'method not found' code -32601"

  # --- tools/call: millennium_diag ---

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":false}}}')
  assert_contains "$log" "millennium diag --json" "${tag} millennium_diag (doctor:false) prefers Go: millennium diag --json"
  assert_not_contains "$log" "millennium-diag" "${tag} millennium_diag (doctor:false) does not use long-name helper when Go is present"
  assert_not_contains "$log" "sudo -n" "${tag} millennium_diag (doctor:false) does not escalate to sudo"

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":true}}}')
  assert_contains "$log" "millennium diag doctor" "${tag} millennium_diag (doctor:true) prefers Go: millennium diag doctor"
  assert_contains "$log" "sudo -n" "${tag} millennium_diag (doctor:true) escalates via sudo -n"
  assert_not_contains "$log" "millennium-diag" "${tag} millennium_diag (doctor:true) does not use long-name when Go is present"

  log=$(
    MILLENNIUM_MCP_LONGNAMES=1 run_mcp_stderr \
      '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":false}}}'
  )
  assert_contains "$log" "millennium-diag --json" "${tag} MILLENNIUM_MCP_LONGNAMES=1 forces millennium-diag --json"

  log=$(
    MILLENNIUM_MCP_LONGNAMES=1 run_mcp_stderr \
      '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":true}}}'
  )
  assert_contains "$log" "millennium-diag doctor" "${tag} MILLENNIUM_MCP_LONGNAMES=1 forces long-name doctor elevate"
  assert_contains "$log" "sudo -n" "${tag} MILLENNIUM_MCP_LONGNAMES=1 doctor still escalates via sudo -n"

  # --- tools/call: millennium_theme / schedule ---

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"millennium_theme","arguments":{"action":"list"}}}')
  assert_contains "$log" "millennium theme list --json" "${tag} millennium_theme (action:list) prefers Go: millennium theme list --json"
  assert_not_contains "$log" "millennium-theme" "${tag} millennium_theme list does not use long-name when Go is present"

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":50,"method":"tools/call","params":{"name":"millennium_schedule","arguments":{"action":"status"}}}')
  assert_contains "$log" "millennium schedule status" "${tag} millennium_schedule status prefers Go dispatcher"
  assert_not_contains "$log" "sudo -n" "${tag} millennium_schedule status does not escalate"

  resp=$(run_mcp '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"millennium_theme","arguments":{"action":"rm -rf"}}}')
  assert_contains "$resp" '"isError": true' "${tag} millennium_theme rejects an action outside its declared enum"
  assert_contains "$resp" "invalid action" "${tag} millennium_theme's rejection message explains the invalid action"

  resp=$(run_mcp '{"jsonrpc":"2.0","id":61,"method":"tools/call","params":{"name":"millennium_theme","arguments":{"action":"install","theme":"../../bad-path"}}}')
  assert_contains "$resp" '"isError": true' "${tag} millennium_theme rejects a theme containing path traversal"
  assert_contains "$resp" "invalid characters" "${tag} millennium_theme's rejection message explains the theme has invalid characters"

  resp=$(run_mcp '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"millennium_schedule","arguments":{"action":"pre-update"}}}')
  assert_contains "$resp" '"isError": true' "${tag} millennium_schedule rejects the internal-only 'pre-update' action"
  assert_contains "$resp" "invalid action" "${tag} millennium_schedule's rejection message explains the invalid action"

  # --- tools/call: millennium_upgrade ---

  resp=$(run_mcp '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"nightly"}}}')
  assert_contains "$resp" '"isError": true' "${tag} millennium_upgrade rejects a channel outside its declared enum"
  assert_contains "$resp" "invalid channel" "${tag} millennium_upgrade's rejection message explains the invalid channel"

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"beta"}}}')
  assert_contains "$log" "millennium upgrade --channel beta" "${tag} millennium_upgrade (channel:beta) prefers Go dispatcher"
  assert_contains "$log" "sudo -n" "${tag} millennium_upgrade escalates via sudo -n"

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":83,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"main"}}}')
  assert_contains "$log" "millennium upgrade --channel main" "${tag} millennium_upgrade (channel:main) prefers Go dispatcher"

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":80,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"beta","force":true}}}')
  assert_contains "$log" "millennium upgrade --channel beta --force" "${tag} millennium_upgrade (force:true) passes --force flag"

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":81,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"stable","rollback":"list"}}}')
  assert_contains "$log" "millennium upgrade --channel stable --rollback list" "${tag} millennium_upgrade (rollback:list) passes --rollback list"

  log=$(
    MILLENNIUM_MCP_LONGNAMES=1 run_mcp_stderr \
      '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"beta"}}}'
  )
  assert_contains "$log" "millennium-upgrade --channel beta" "${tag} MILLENNIUM_MCP_LONGNAMES=1 forces millennium-upgrade"

  resp=$(run_mcp '{"jsonrpc":"2.0","id":82,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"stable","rollback":"../invalid"}}}')
  assert_contains "$resp" '"isError": true' "${tag} millennium_upgrade with invalid rollback pattern returns error"

  # --- tools/call: millennium_purge ---

  resp=$(run_mcp '{"jsonrpc":"2.0","id":83,"method":"tools/call","params":{"name":"millennium_purge","arguments":{}}}')
  assert_contains "$resp" '"isError": true' "${tag} millennium_purge without confirm returns error"
  assert_contains "$resp" "confirm=true" "${tag} millennium_purge without confirm explains confirm=true is required"

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":83,"method":"tools/call","params":{"name":"millennium_purge","arguments":{"confirm":true}}}')
  assert_contains "$log" "millennium purge --yes" "${tag} millennium_purge with confirm=true prefers Go: millennium purge --yes"
  assert_contains "$log" "sudo -n" "${tag} millennium_purge escalates via sudo -n"

  log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":87,"method":"tools/call","params":{"name":"millennium_purge","arguments":{"confirm":false,"dry_run":true}}}')
  assert_contains "$log" "millennium purge --dry-run" "${tag} millennium_purge with dry_run=true prefers Go dispatcher"

  # --- TEST_SUITE_RUN skip path ---
  for tool_case in \
    'millennium_repair|millennium-repair|{"jsonrpc":"2.0","id":84,"method":"tools/call","params":{"name":"millennium_repair","arguments":{}}}' \
    'millennium_upgrade|millennium-upgrade|{"jsonrpc":"2.0","id":85,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"stable"}}}' \
    'millennium_purge|millennium-purge|{"jsonrpc":"2.0","id":86,"method":"tools/call","params":{"name":"millennium_purge","arguments":{"confirm":true}}}'; do
    IFS='|' read -r tool_name bin_name request <<< "$tool_case"
    rm -f "${MOCK_BIN}/millennium" "${MOCK_BIN}/${bin_name}"
    log=$(MILLENNIUM_MCP_LONGNAMES=1 run_mcp_stderr "$request")
    assert_contains "$log" "sudo -n" "${tag} ${tool_name} still logs the production sudo command line under TEST_SUITE_RUN"
    assert_contains "$log" "Skipping host execution" "${tag} ${tool_name} skips host execution when no MOCK_BIN stub exists"
    mock_cmd "millennium" "exit 0"
    mock_cmd "$bin_name" "exit 0"
  done

  # --- unknown tool ---

  resp=$(run_mcp '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"not_a_real_tool","arguments":{}}}')
  assert_contains "$resp" '"isError": true' "${tag} an unknown tool name reports isError:true"
  assert_contains "$resp" "Unknown tool" "${tag} an unknown tool name's error message names the tool as unknown"

  # --- --version ---
  case "${MCP_IMPL_ACTIVE}" in
    python)
      out=$(MILLENNIUM_MCP_PYTHON=1 python3 "$MCP_PY" --version 2>&1)
      ;;
    go)
      out=$("$GO_BIN" mcp --version 2>&1)
      ;;
  esac
  rc=$?
  assert_success "$rc" "${tag} mcp --version exits 0"
  assert_contains "$out" "millennium-mcp" "${tag} mcp --version prints command name"
  assert_contains "$out" "$EXPECTED_VERSION" "${tag} mcp --version prints VERSION file value"
}

for MCP_IMPL_ACTIVE in "${IMPLS[@]}"; do
  export MCP_IMPL_ACTIVE
  echo -e "${YELLOW}--- MCP protocol suite (${MCP_IMPL_ACTIVE}) ---${NC}"
  run_protocol_suite
done

# --- Python-only: missing system binary seam ---
rm -f "${MOCK_BIN}/millennium" "${MOCK_BIN}/millennium-repair"
missing_bin_log=$(
  {
    MILLENNIUM_MCP_LONGNAMES=1 MILLENNIUM_MCP_PYTHON=1 python3 - "$MCP_PY" << 'PYEOF' >/dev/null
import importlib.util
import sys

mcp_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("millennium_mcp", mcp_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.find_executable = lambda _cmd: None
mod.handle_tool_call("millennium_repair", {})
PYEOF
  } 2>&1
)
assert_contains "$missing_bin_log" "sudo -n" "missing system binary still logs sudo -n under TEST_SUITE_RUN"
assert_contains "$missing_bin_log" "Skipping host execution" "missing system binary skips host execution under TEST_SUITE_RUN"
assert_contains "$missing_bin_log" "millennium-repair" "missing system binary logs the tool name in the command line"
mock_cmd "millennium" "exit 0"
mock_cmd "millennium-repair" "exit 0"

# --- Python-only: run_cmd() timeout handling ---
mock_cmd "mcp-hang-test" 'sleep 5'
timeout_result=$(MILLENNIUM_MCP_PYTHON=1 python3 - "$MCP_PY" << 'PYEOF'
import importlib.util
import sys

mcp_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("millennium_mcp", mcp_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

result = mod.run_cmd(["mcp-hang-test"], timeout=1)
print(result["isError"])
print(result["content"][0]["text"])
PYEOF
)
timeout_is_error=$(echo "$timeout_result" | sed -n '1p')
timeout_msg=$(echo "$timeout_result" | sed -n '2p')
assert_equals "True" "$timeout_is_error" "run_cmd() reports isError=True when the underlying command exceeds its timeout"
assert_contains "$timeout_msg" "timed out" "run_cmd()'s timeout error message explains the command timed out"
rm -f "${MOCK_BIN}/mcp-hang-test"

# --- --register (Go native + Python escape hatch) ---
run_register_suite() {
  local label="$1"
  local -a cmd=("${@:2}")
  local fake
  fake=$(mktemp -d)
  mkdir -p "${fake}/.config/Claude" "${fake}/.codeium/windsurf" "${fake}/.cursor"
  echo "{}" > "${fake}/.config/Claude/claude_desktop_config.json"

  out=$(HOME="$fake" "${cmd[@]}" 2>&1)
  rc=$?
  assert_success "$rc" "${label} --register exits 0 when config directories exist"
  assert_contains "$out" "Registering" "${label} --register output contains registration message"
  assert_contains "$out" "Successfully registered in Claude Desktop" "${label} --register confirms Claude Desktop"
  assert_contains "$out" "Successfully registered in Cursor" "${label} --register confirms Cursor"
  assert_contains "$out" "Manual config snippet" "${label} --register prints a manual config snippet"
  assert_contains "$out" '"mcpServers"' "${label} --register snippet includes mcpServers"
  assert_contains "$out" "Restart" "${label} --register tips restarting AI clients"

  assert_file_exists "${fake}/.config/Claude/claude_desktop_config.json" "${label} claude_desktop_config.json exists"
  config_contents=$(cat "${fake}/.config/Claude/claude_desktop_config.json")
  assert_contains "$config_contents" "millennium-helpers" "${label} claude config contains millennium-helpers"
  assert_contains "$config_contents" "millennium-mcp" "${label} claude config command is millennium-mcp"

  assert_file_exists "${fake}/.cursor/mcp.json" "${label} Cursor mcp.json exists after --register"
  cursor_contents=$(cat "${fake}/.cursor/mcp.json")
  assert_contains "$cursor_contents" "millennium-helpers" "${label} Cursor mcp.json contains millennium-helpers"
  rm -rf "$fake"
}

if [[ -x "${GO_BIN}" ]]; then
  run_register_suite "millennium mcp" "$GO_BIN" mcp --register
  # argv0 twin: copy/symlink as millennium-mcp
  MCP_ARGV0=$(mktemp)
  cp -f "$GO_BIN" "$MCP_ARGV0"
  chmod +x "$MCP_ARGV0"
  # basename must be millennium-mcp for argv0 routing
  MCP_NAMED="$(dirname "$MCP_ARGV0")/millennium-mcp"
  mv -f "$MCP_ARGV0" "$MCP_NAMED"
  run_register_suite "millennium-mcp argv0" "$MCP_NAMED" --register
  rm -f "$MCP_NAMED"
fi
run_register_suite "python millennium-mcp" env MILLENNIUM_MCP_PYTHON=1 python3 "$MCP_PY" --register

# --- Python-only: argparse help / invalid / TypedDict ---
out=$(MILLENNIUM_MCP_PYTHON=1 python3 "$MCP_PY" --help 2>&1)
rc=$?
assert_success "$rc" "millennium-mcp --help exits 0"
assert_contains "$out" "usage:" "millennium-mcp --help prints usage help"

out=$(MILLENNIUM_MCP_PYTHON=1 python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('millennium_mcp', '${MCP_PY}')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert hasattr(mod, 'DiagArgs')
assert hasattr(mod, 'ThemeArgs')
assert hasattr(mod, 'UpgradeArgs')
assert hasattr(mod, 'ScheduleArgs')
diag = mod.DiagArgs(doctor=True)
assert diag['doctor'] is True
theme = mod.ThemeArgs(action='list')
assert theme['action'] == 'list'
print('typeddicts-ok')
" 2>&1)
rc=$?
assert_success "$rc" "millennium-mcp TypedDict helpers import and construct"
assert_contains "$out" "typeddicts-ok" "millennium-mcp TypedDict smoke check prints ok"

out=$(MILLENNIUM_MCP_PYTHON=1 python3 "$MCP_PY" --invalid-flag 2>&1)
rc=$?
assert_failure "$rc" "millennium-mcp with invalid flag exits non-zero"
assert_contains "$out" "unrecognized arguments" "millennium-mcp reports unrecognized arguments"

# Go native help when built
if [[ -x "${GO_BIN}" ]]; then
  out=$("$GO_BIN" mcp --help 2>&1)
  rc=$?
  assert_success "$rc" "millennium mcp --help exits 0"
  assert_contains "$out" "Usage: millennium mcp" "millennium mcp --help prints usage"
fi

print_summary
