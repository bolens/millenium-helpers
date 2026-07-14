#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-mcp.py
#
# millennium-mcp.py is the newest, most externally-facing component in this
# repo: it exposes the other millennium-* scripts to untrusted MCP client
# input (a JSON-RPC request over stdin/stdout). Prior to this test file it
# had zero coverage of its protocol handling, tool dispatch, or the
# server-side validation/timeout hardening added alongside these tests.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

MCP_PY="${REPO_ROOT}/scripts/millennium-mcp.py"

setup_mock_bin
# Go dispatcher stub: Phase 5a prefers `millennium <feature>` for non-elevate tools.
mock_cmd "millennium" "exit 0"
mock_cmd "millennium-diag" "exit 0"
mock_cmd "millennium-theme" "exit 0"
mock_cmd "millennium-upgrade" "exit 0"
mock_cmd "millennium-schedule" "exit 0"
mock_cmd "millennium-repair" "exit 0"
mock_cmd "millennium-purge" "exit 0"
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: millennium-mcp.py ===${NC}"

# Sends one or more JSON-RPC request lines to the server over stdin and
# returns all stdout response lines. Each request/response is a single JSON
# line, so callers can pick out the Nth response with `sed -n 'Np'`.
run_mcp() {
  printf '%s\n' "$@" | python3 "$MCP_PY" 2>/dev/null
}

# Same as run_mcp() but returns stderr instead (where run_cmd() logs the
# exact resolved command line, e.g. "[MCP LOG] Executing: /path/millennium-
# diag --json"). Argument-construction correctness is asserted against this
# log line rather than mocked stdout, since find_executable() prefers
# /usr/local/bin and /usr/bin over $PATH -- on a machine that already has
# millennium-helpers installed system-wide, a PATH-only mock would silently
# be shadowed by the real installed script.
#
# Under TEST_SUITE_RUN, millennium-mcp.py still logs that production command
# line but executes the MOCK_BIN stub (or skips) so sudo/Steam are never
# touched on the developer host.
run_mcp_stderr() {
  { printf '%s\n' "$@" | python3 "$MCP_PY" >/dev/null; } 2>&1
}

# --- initialize ---

resp=$(run_mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
assert_valid_json "$resp" "initialize response is valid JSON"
assert_contains "$resp" '"protocolVersion"' "initialize response includes a protocolVersion"
assert_contains "$resp" '"id": 1' "initialize response echoes the request id"

# --- tools/list ---

resp=$(run_mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')
assert_valid_json "$resp" "tools/list response is valid JSON"
for tool in millennium_diag millennium_theme millennium_upgrade millennium_schedule millennium_repair millennium_purge; do
  assert_contains "$resp" "\"${tool}\"" "tools/list includes the ${tool} tool"
done
assert_contains "$resp" '"confirm"' "tools/list millennium_purge schema includes confirm"
assert_contains "$resp" '"dry_run"' "tools/list millennium_purge schema includes dry_run"

# --- unknown method ---

resp=$(run_mcp '{"jsonrpc":"2.0","id":3,"method":"not/a/real/method","params":{}}')
assert_contains "$resp" '"error"' "an unrecognized method returns a JSON-RPC error"
assert_contains "$resp" '-32601' "unrecognized method returns JSON-RPC 'method not found' code -32601"

# --- tools/call: millennium_diag builds the expected command line ---

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":false}}}')
assert_contains "$log" "millennium diag --json" "millennium_diag (doctor:false) prefers Go: millennium diag --json"
assert_not_contains "$log" "millennium-diag" "millennium_diag (doctor:false) does not use long-name helper when Go is present"
assert_not_contains "$log" "sudo -n" "millennium_diag (doctor:false) does not escalate to sudo"

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":true}}}')
assert_contains "$log" "millennium diag doctor" "millennium_diag (doctor:true) prefers Go: millennium diag doctor"
assert_contains "$log" "sudo -n" "millennium_diag (doctor:true) escalates via sudo -n"
assert_not_contains "$log" "millennium-diag" "millennium_diag (doctor:true) does not use long-name when Go is present"

# Escape hatch: force long-name even when Go dispatcher is on PATH
log=$(
  MILLENNIUM_MCP_LONGNAMES=1 run_mcp_stderr \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":false}}}'
)
assert_contains "$log" "millennium-diag --json" "MILLENNIUM_MCP_LONGNAMES=1 forces millennium-diag --json"

log=$(
  MILLENNIUM_MCP_LONGNAMES=1 run_mcp_stderr \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":true}}}'
)
assert_contains "$log" "millennium-diag doctor" "MILLENNIUM_MCP_LONGNAMES=1 forces long-name doctor elevate"
assert_contains "$log" "sudo -n" "MILLENNIUM_MCP_LONGNAMES=1 doctor still escalates via sudo -n"

# --- tools/call: millennium_theme with a valid action builds the expected command line ---

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"millennium_theme","arguments":{"action":"list"}}}')
assert_contains "$log" "millennium theme list --json" "millennium_theme (action:list) prefers Go: millennium theme list --json"
assert_not_contains "$log" "millennium-theme" "millennium_theme list does not use long-name when Go is present"

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":50,"method":"tools/call","params":{"name":"millennium_schedule","arguments":{"action":"status"}}}')
assert_contains "$log" "millennium schedule status" "millennium_schedule status prefers Go dispatcher"
assert_not_contains "$log" "sudo -n" "millennium_schedule status does not escalate"

# --- tools/call: millennium_theme with an invalid action is rejected server-side ---
# (get_tools_list() declares an "enum" for action, but nothing enforces it
# unless handle_tool_call() checks explicitly - a client could otherwise
# send anything through to the shell script.)

resp=$(run_mcp '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"millennium_theme","arguments":{"action":"rm -rf"}}}')
assert_contains "$resp" '"isError": true' "millennium_theme rejects an action outside its declared enum"
assert_contains "$resp" "invalid action" "millennium_theme's rejection message explains the invalid action"

# --- tools/call: millennium_theme with an invalid theme is rejected ---

resp=$(run_mcp '{"jsonrpc":"2.0","id":61,"method":"tools/call","params":{"name":"millennium_theme","arguments":{"action":"install","theme":"../../bad-path"}}}')
assert_contains "$resp" '"isError": true' "millennium_theme rejects a theme containing path traversal"
assert_contains "$resp" "invalid characters" "millennium_theme's rejection message explains the theme has invalid characters"

# --- tools/call: millennium_schedule refuses internal-only subcommands ---
# millennium-schedule.sh accepts internal "pre-update"/"post-update"
# subcommands (used by the systemd/cron hooks) that close/relaunch Steam
# outside of the normal enable/disable/status flow. The MCP tool schema
# only declares enable/disable/status, so the server must reject anything
# else rather than passing it straight to the shell script.

resp=$(run_mcp '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"millennium_schedule","arguments":{"action":"pre-update"}}}')
assert_contains "$resp" '"isError": true' "millennium_schedule rejects the internal-only 'pre-update' action"
assert_contains "$resp" "invalid action" "millennium_schedule's rejection message explains the invalid action"

# --- tools/call: millennium_upgrade with an invalid channel is rejected ---

resp=$(run_mcp '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"nightly"}}}')
assert_contains "$resp" '"isError": true' "millennium_upgrade rejects a channel outside its declared enum"
assert_contains "$resp" "invalid channel" "millennium_upgrade's rejection message explains the invalid channel"

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"beta"}}}')
assert_contains "$log" "millennium upgrade --channel beta" "millennium_upgrade (channel:beta) prefers Go dispatcher"
assert_contains "$log" "sudo -n" "millennium_upgrade escalates via sudo -n"

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":83,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"main"}}}')
assert_contains "$log" "millennium upgrade --channel main" "millennium_upgrade (channel:main) prefers Go dispatcher"

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":80,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"beta","force":true}}}')
assert_contains "$log" "millennium upgrade --channel beta --force" "millennium_upgrade (force:true) passes --force flag"

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":81,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"stable","rollback":"list"}}}')
assert_contains "$log" "millennium upgrade --channel stable --rollback list" "millennium_upgrade (rollback:list) passes --rollback list"

log=$(
  MILLENNIUM_MCP_LONGNAMES=1 run_mcp_stderr \
    '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"beta"}}}'
)
assert_contains "$log" "millennium-upgrade --channel beta" "MILLENNIUM_MCP_LONGNAMES=1 forces millennium-upgrade"

resp=$(run_mcp '{"jsonrpc":"2.0","id":82,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"stable","rollback":"../invalid"}}}')
assert_contains "$resp" '"isError": true' "millennium_upgrade with invalid rollback pattern returns error"

# --- tools/call: millennium_purge requires confirm ---

resp=$(run_mcp '{"jsonrpc":"2.0","id":83,"method":"tools/call","params":{"name":"millennium_purge","arguments":{}}}')
assert_contains "$resp" '"isError": true' "millennium_purge without confirm returns error"
assert_contains "$resp" "confirm=true" "millennium_purge without confirm explains confirm=true is required"

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":83,"method":"tools/call","params":{"name":"millennium_purge","arguments":{"confirm":true}}}')
assert_contains "$log" "millennium purge --yes" "millennium_purge with confirm=true prefers Go: millennium purge --yes"
assert_contains "$log" "sudo -n" "millennium_purge escalates via sudo -n"

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":87,"method":"tools/call","params":{"name":"millennium_purge","arguments":{"confirm":false,"dry_run":true}}}')
assert_contains "$log" "millennium purge --dry-run" "millennium_purge with dry_run=true prefers Go dispatcher"

# --- tools/call under TEST_SUITE_RUN must not exec system helpers ---
# Without MOCK_BIN stubs, sudo -n could run real helpers and relaunch Steam.
# Force long-name + clear stubs so the server logs production argv then skips.
for tool_case in \
  'millennium_repair|millennium-repair|{"jsonrpc":"2.0","id":84,"method":"tools/call","params":{"name":"millennium_repair","arguments":{}}}' \
  'millennium_upgrade|millennium-upgrade|{"jsonrpc":"2.0","id":85,"method":"tools/call","params":{"name":"millennium_upgrade","arguments":{"channel":"stable"}}}' \
  'millennium_purge|millennium-purge|{"jsonrpc":"2.0","id":86,"method":"tools/call","params":{"name":"millennium_purge","arguments":{"confirm":true}}}'; do
  IFS='|' read -r tool_name bin_name request <<< "$tool_case"
  rm -f "${MOCK_BIN}/millennium" "${MOCK_BIN}/${bin_name}"
  log=$(MILLENNIUM_MCP_LONGNAMES=1 run_mcp_stderr "$request")
  assert_contains "$log" "sudo -n" "${tool_name} still logs the production sudo command line under TEST_SUITE_RUN"
  assert_contains "$log" "Skipping host execution" "${tool_name} skips host execution when no MOCK_BIN stub exists"
  mock_cmd "millennium" "exit 0"
  mock_cmd "$bin_name" "exit 0"
done

# CI runners often have no /usr/bin/millennium-* at all. Force that path even
# on developer hosts that do have system installs, so the missing-binary
# TEST_SUITE_RUN branch stays covered. Clear the MOCK_BIN stub too — otherwise
# _run_under_test_suite would execute it instead of taking the skip path.
rm -f "${MOCK_BIN}/millennium" "${MOCK_BIN}/millennium-repair"
missing_bin_log=$(
  {
    MILLENNIUM_MCP_LONGNAMES=1 python3 - "$MCP_PY" << 'PYEOF' >/dev/null
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

# --- tools/call: unknown tool name ---

resp=$(run_mcp '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"not_a_real_tool","arguments":{}}}')
assert_contains "$resp" '"isError": true' "an unknown tool name reports isError:true"
assert_contains "$resp" "Unknown tool" "an unknown tool name's error message names the tool as unknown"

# --- run_cmd() timeout handling (direct import; avoids waiting out the
# real multi-minute production timeouts declared in the module) ---

mock_cmd "mcp-hang-test" 'sleep 5'
timeout_result=$(python3 - "$MCP_PY" << 'PYEOF'
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

# --- --register/--install command line arguments ---

FAKE_HOME_MCP=$(mktemp -d)
mkdir -p "${FAKE_HOME_MCP}/.config/Claude"
mkdir -p "${FAKE_HOME_MCP}/.codeium/windsurf"
mkdir -p "${FAKE_HOME_MCP}/.cursor"

# Write an empty config file to Claude
echo "{}" > "${FAKE_HOME_MCP}/.config/Claude/claude_desktop_config.json"

out=$(HOME="$FAKE_HOME_MCP" python3 "$MCP_PY" --register 2>&1)
rc=$?
assert_success "$rc" "millennium-mcp --register exits 0 when config directories exist"
assert_contains "$out" "Registering" "millennium-mcp --register output contains registration message"
assert_contains "$out" "Successfully registered in Claude Desktop" "millennium-mcp --register output confirms Claude Desktop registration"
assert_contains "$out" "Successfully registered in Cursor" "millennium-mcp --register output confirms Cursor registration"
assert_contains "$out" "Manual config snippet" "millennium-mcp --register prints a manual config snippet"
assert_contains "$out" '"mcpServers"' "millennium-mcp --register snippet includes mcpServers"
assert_contains "$out" "Restart" "millennium-mcp --register tips restarting AI clients"

# Verify config contents
assert_file_exists "${FAKE_HOME_MCP}/.config/Claude/claude_desktop_config.json" "claude_desktop_config.json exists"
config_contents=$(cat "${FAKE_HOME_MCP}/.config/Claude/claude_desktop_config.json")
assert_contains "$config_contents" "millennium-helpers" "claude_desktop_config.json contains the millennium-helpers key"
assert_contains "$config_contents" "millennium-mcp" "claude_desktop_config.json contains the millennium-mcp command"

assert_file_exists "${FAKE_HOME_MCP}/.cursor/mcp.json" "Cursor mcp.json exists after --register"
cursor_contents=$(cat "${FAKE_HOME_MCP}/.cursor/mcp.json")
assert_contains "$cursor_contents" "millennium-helpers" "Cursor mcp.json contains the millennium-helpers key"

rm -rf "$FAKE_HOME_MCP"

# --- --help / --version and invalid options ---
out=$(python3 "$MCP_PY" --help 2>&1)
rc=$?
assert_success "$rc" "millennium-mcp --help exits 0"
assert_contains "$out" "usage:" "millennium-mcp --help prints usage help"

out=$(python3 "$MCP_PY" --version 2>&1)
rc=$?
assert_success "$rc" "millennium-mcp --version exits 0"
assert_contains "$out" "millennium-mcp" "millennium-mcp --version prints command name"
assert_contains "$out" "$EXPECTED_VERSION" "millennium-mcp --version prints VERSION file value"

# TypedDict arg shapes used by tool handlers must import cleanly
out=$(python3 -c "
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

out=$(python3 "$MCP_PY" --invalid-flag 2>&1)
rc=$?
assert_failure "$rc" "millennium-mcp with invalid flag exits non-zero"
assert_contains "$out" "unrecognized arguments" "millennium-mcp reports unrecognized arguments"

print_summary
