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

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

MCP_PY="${REPO_ROOT}/scripts/millennium-mcp.py"

setup_mock_bin
mock_cmd "millennium-diag" "exit 0"
mock_cmd "millennium-theme" "exit 0"
mock_cmd "millennium-upgrade-beta" "exit 0"
mock_cmd "millennium-upgrade-stable" "exit 0"
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

# --- unknown method ---

resp=$(run_mcp '{"jsonrpc":"2.0","id":3,"method":"not/a/real/method","params":{}}')
assert_contains "$resp" '"error"' "an unrecognized method returns a JSON-RPC error"
assert_contains "$resp" '-32601' "unrecognized method returns JSON-RPC 'method not found' code -32601"

# --- tools/call: millennium_diag builds the expected command line ---

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":false}}}')
assert_contains "$log" "millennium-diag --json" "millennium_diag (doctor:false) invokes millennium-diag --json"
assert_not_contains "$log" "sudo -n" "millennium_diag (doctor:false) does not escalate to sudo"

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{"doctor":true}}}')
assert_contains "$log" "millennium-diag doctor" "millennium_diag (doctor:true) invokes millennium-diag doctor"
assert_contains "$log" "sudo -n" "millennium_diag (doctor:true) escalates via sudo -n"

# --- tools/call: millennium_theme with a valid action builds the expected command line ---

log=$(run_mcp_stderr '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"millennium_theme","arguments":{"action":"list"}}}')
assert_contains "$log" "millennium-theme list --json" "millennium_theme (action:list) invokes millennium-theme list --json"

# --- tools/call: millennium_theme with an invalid action is rejected server-side ---
# (get_tools_list() declares an "enum" for action, but nothing enforces it
# unless handle_tool_call() checks explicitly - a client could otherwise
# send anything through to the shell script.)

resp=$(run_mcp '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"millennium_theme","arguments":{"action":"rm -rf"}}}')
assert_contains "$resp" '"isError": true' "millennium_theme rejects an action outside its declared enum"
assert_contains "$resp" "invalid action" "millennium_theme's rejection message explains the invalid action"

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

print_summary
