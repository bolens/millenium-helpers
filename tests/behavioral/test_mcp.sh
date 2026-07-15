#!/usr/bin/env bash
# Behavioral tests for millennium MCP (Go native server).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

GO_BIN="${GO_BIN:-${REPO_ROOT}/bin/millennium}"

setup_mock_bin
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
  echo "Building Go binary for MCP suite…"
  make -C "${REPO_ROOT}" build
  [[ -x "${GO_BIN}" ]] || {
    echo "error: expected ${GO_BIN} after make build" >&2
    exit 1
  }
}

ensure_go_bin

echo -e "${YELLOW}=== Behavioral tests: millennium MCP (go) ===${NC}"

run_mcp() {
  printf '%s\n' "$@" | "$GO_BIN" mcp 2>/dev/null
}

run_mcp_stderr() {
  { printf '%s\n' "$@" | "$GO_BIN" mcp >/dev/null; } 2>&1
}

tag="[go]"

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

# --- notifications (initialized has no response) ---
resp=$(run_mcp '{"jsonrpc":"2.0","method":"initialized","params":{}}')
assert_equals "" "$resp" "${tag} initialized notification produces no response"

# --- tools/call: diag ---
resp=$(run_mcp '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"millennium_diag","arguments":{}}}')
assert_valid_json "$resp" "${tag} tools/call millennium_diag is valid JSON"
assert_contains "$resp" '"isError": false' "${tag} tools/call millennium_diag succeeds under mocks"

# --- tools/call: purge requires confirm ---
resp=$(run_mcp '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"millennium_purge","arguments":{}}}')
assert_contains "$resp" '"isError": true' "${tag} purge without confirm is an error"
assert_contains "$resp" 'confirm' "${tag} purge without confirm mentions confirm"

# --- tools/call: purge dry_run ---
resp=$(run_mcp '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"millennium_purge","arguments":{"confirm":true,"dry_run":true}}}')
assert_contains "$resp" '"isError": false' "${tag} purge with confirm+dry_run succeeds"

# --- unknown tool ---
resp=$(run_mcp '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"not_a_real_tool","arguments":{}}}')
assert_contains "$resp" '"isError": true' "${tag} an unknown tool name reports isError:true"
assert_contains "$resp" "Unknown tool" "${tag} an unknown tool name's error message names the tool as unknown"

# --- --version ---
out=$("$GO_BIN" mcp --version 2>&1)
rc=$?
assert_success "$rc" "${tag} mcp --version exits 0"
assert_contains "$out" "millennium-mcp" "${tag} mcp --version prints command name"
assert_contains "$out" "$EXPECTED_VERSION" "${tag} mcp --version prints VERSION file value"

# --- missing system binary seam under TEST_SUITE_RUN ---
rm -f "${MOCK_BIN}/millennium" "${MOCK_BIN}/millennium-repair"
missing_bin_log=$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"millennium_repair","arguments":{}}}' \
      | MILLENNIUM_MCP_LONGNAMES=1 TEST_SUITE_RUN=1 "$GO_BIN" mcp >/dev/null
  } 2>&1
)
assert_contains "$missing_bin_log" "sudo -n" "missing system binary still logs sudo -n under TEST_SUITE_RUN"
assert_contains "$missing_bin_log" "Skipping host execution" "missing system binary skips host execution under TEST_SUITE_RUN"
assert_contains "$missing_bin_log" "millennium-repair" "missing system binary logs the tool name in the command line"
mock_cmd "millennium" "exit 0"
mock_cmd "millennium-repair" "exit 0"

# --- --register ---
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

run_register_suite "millennium mcp" "$GO_BIN" mcp --register
MCP_ARGV0=$(mktemp)
cp -f "$GO_BIN" "$MCP_ARGV0"
chmod +x "$MCP_ARGV0"
MCP_NAMED="$(dirname "$MCP_ARGV0")/millennium-mcp"
mv -f "$MCP_ARGV0" "$MCP_NAMED"
run_register_suite "millennium-mcp argv0" "$MCP_NAMED" --register
rm -f "$MCP_NAMED"

out=$("$GO_BIN" mcp --help 2>&1)
rc=$?
assert_success "$rc" "millennium mcp --help exits 0"
assert_contains "$out" "Usage: millennium mcp" "millennium mcp --help prints usage"

out=$("$GO_BIN" mcp --invalid-flag 2>&1)
rc=$?
assert_failure "$rc" "millennium mcp with invalid flag exits non-zero"

print_summary
