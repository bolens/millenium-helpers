#!/usr/bin/env bash
# Unit tests for scripts/common.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

export DRY_RUN=true
# shellcheck source=../../scripts/common.sh
source "${REPO_ROOT}/scripts/common.sh"

echo -e "${YELLOW}=== Unit tests: common.sh ===${NC}"

# --- log_msg / log_info / log_warn / log_error ---

out=$(log_info "hello world")
assert_contains "$out" "[INFO]" "log_info includes INFO tag"
assert_contains "$out" "hello world" "log_info includes message"
assert_contains "$out" "$(basename "$0")" "log_info includes calling script name"

out=$(log_warn "careful now")
assert_contains "$out" "[WARN]" "log_warn includes WARN tag"
assert_contains "$out" "careful now" "log_warn includes message"

out=$(log_error "boom" 2>&1 1>/dev/null)
assert_contains "$out" "[ERROR]" "log_error includes ERROR tag"
assert_contains "$out" "boom" "log_error includes message"

stdout=$(log_error "should not be on stdout" 2>/dev/null)
assert_equals "" "$stdout" "log_error writes only to stderr, not stdout"

# Timestamp format sanity check: [YYYY-MM-DD HH:MM:SS]
out=$(log_info "ts check")
if [[ "$out" =~ \[[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]; then
  assert_equals "0" "0" "log_msg timestamp matches expected format"
else
  assert_equals "timestamp-format" "$out" "log_msg timestamp matches expected format"
fi

# --- execute() ---

DRY_RUN=true
out=$(execute echo "hello world")
assert_contains "$out" "[DRY RUN]" "execute (dry-run) prints DRY RUN marker"
assert_contains "$out" "echo hello world" "execute (dry-run) echoes the command and args"
assert_not_contains "$out" $'hello world\n[DRY RUN]' "execute (dry-run) does not actually run the command"

DRY_RUN=false
marker_file=$(mktemp)
execute touch "$marker_file.executed"
assert_file_exists "${marker_file}.executed" "execute (live) actually runs the given command"
rm -f "$marker_file" "${marker_file}.executed"

DRY_RUN=true
# --- write_file() ---

target_file=$(mktemp -u)
out=$(echo "file contents" | write_file "$target_file")
assert_contains "$out" "[DRY RUN]" "write_file (dry-run) prints DRY RUN marker"
assert_contains "$out" "$target_file" "write_file (dry-run) mentions target path"
assert_file_not_exists "$target_file" "write_file (dry-run) does not create the file"

DRY_RUN=false
target_file2=$(mktemp -u)
echo "real contents" | write_file "$target_file2"
assert_file_exists "$target_file2" "write_file (live) creates the target file"
assert_equals "real contents" "$(cat "$target_file2" 2>/dev/null)" "write_file (live) writes the exact given contents"
rm -f "$target_file2"
DRY_RUN=true

# --- resolve_helper_path() ---

touch "${MOCK_BIN}/millennium-diag-test-mock"
chmod +x "${MOCK_BIN}/millennium-diag-test-mock"
resolved=$(resolve_helper_path "millennium-diag-test-mock")
assert_equals "${MOCK_BIN}/millennium-diag-test-mock" "$resolved" "resolve_helper_path finds an executable on PATH"
rm -f "${MOCK_BIN}/millennium-diag-test-mock"

resolved=$(resolve_helper_path "millennium-totally-nonexistent-tool")
assert_equals "/usr/local/bin/millennium-totally-nonexistent-tool" "$resolved" "resolve_helper_path falls back to /usr/local/bin when not found on PATH"

# --- fetch_github_commit() ---

# jq path: mock curl + jq to return a fixed sha
mock_cmd "jq" 'read -r _; echo "abc123def456"'
mock_cmd_output "curl" '{"sha":"abc123def456"}'
sha=$(fetch_github_commit "someowner" "somerepo")
assert_equals "abc123def456" "$sha" "fetch_github_commit (jq path) parses SHA from curl+jq output"
rm -f "${MOCK_BIN}/jq" "${MOCK_BIN}/curl"

# python3 fallback path: no jq on PATH, curl returns real JSON, python3 is the real interpreter
mock_cmd "curl" 'cat << '"'"'JSONEOF'"'"'
[{"sha": "deadbeef00112233"}]
JSONEOF'
sha=$(fetch_github_commit "someowner" "somerepo")
assert_equals "deadbeef00112233" "$sha" "fetch_github_commit (python3 fallback) parses SHA when jq is unavailable"
rm -f "${MOCK_BIN}/curl"

# Failure path: curl fails / returns garbage -> empty string, no crash
mock_cmd "curl" 'exit 1'
sha=$(fetch_github_commit "someowner" "somerepo")
assert_equals "" "$sha" "fetch_github_commit returns empty string when curl fails"
rm -f "${MOCK_BIN}/curl"

# --- fetch_github_latest_stable_tag() ---

mock_cmd "curl" 'cat << '"'"'JSONEOF'"'"'
{"tag_name": "v3.2.0"}
JSONEOF'
tag=$(fetch_github_latest_stable_tag "SteamClientHomebrew" "Millennium")
assert_equals "v3.2.0" "$tag" "fetch_github_latest_stable_tag (python3 fallback) parses tag_name"
rm -f "${MOCK_BIN}/curl"

mock_cmd "jq" 'read -r _; echo "v3.3.0"'
mock_cmd "curl" 'echo "{}"'
tag=$(fetch_github_latest_stable_tag "SteamClientHomebrew" "Millennium")
assert_equals "v3.3.0" "$tag" "fetch_github_latest_stable_tag (jq path) parses tag_name"
rm -f "${MOCK_BIN}/jq" "${MOCK_BIN}/curl"

# --- fetch_github_latest_beta_tag() ---

mock_cmd "curl" 'cat << '"'"'JSONEOF'"'"'
[{"tag_name": "v3.4.0", "prerelease": false}, {"tag_name": "v3.3.0-beta.1", "prerelease": true}]
JSONEOF'
tag=$(fetch_github_latest_beta_tag "SteamClientHomebrew" "Millennium")
assert_equals "v3.3.0-beta.1" "$tag" "fetch_github_latest_beta_tag (python3 fallback) picks first prerelease beta tag, skipping stable"
rm -f "${MOCK_BIN}/curl"

mock_cmd "jq" 'read -r _; echo "v3.3.0-beta.2"'
mock_cmd "curl" 'echo "[]"'
tag=$(fetch_github_latest_beta_tag "SteamClientHomebrew" "Millennium")
assert_equals "v3.3.0-beta.2" "$tag" "fetch_github_latest_beta_tag (jq path) parses beta tag"
rm -f "${MOCK_BIN}/jq" "${MOCK_BIN}/curl"

# --- is_game_running() ---

# In the test environment there is no Steam game process, so this must be false.
if is_game_running; then
  assert_equals "false" "true" "is_game_running returns false when no game process exists"
else
  assert_equals "false" "false" "is_game_running returns false when no game process exists"
fi

# --- relaunch_state_file() / relaunch_steam() / capture_steam_env() ---
#
# capture_steam_env/relaunch_steam now derive the state file path from the
# target user's home directory (via relaunch_state_file()) rather than
# accepting a caller-supplied path, and store it under
# <home>/.local/state/millennium-helpers/relaunch.env instead of predictable
# world-writable /tmp paths (closing a symlink-race privilege-escalation
# vector). Point the mocked "getent" user's home at a throwaway temp dir so
# these tests can exercise the real code path without touching /home.

# Ownership of the state file is checked against the target user before it
# is sourced, so these tests use the real invoking user as the "target
# user" (mirroring the real non-root self-service call path, e.g.
# millennium-schedule.sh's pre/post-update hooks, where target_user is
# always the invoking user).
test_relaunch_user="$(id -un)"
relaunch_test_home=$(mktemp -d)
mock_cmd "getent" 'echo "'"${test_relaunch_user}"':x:1000:1000::'"${relaunch_test_home}"':/bin/bash"'
mock_cmd "runuser" 'echo "runuser called: $*" >> "'"${MOCK_BIN}"'/runuser.calls"'

expected_state_file="${relaunch_test_home}/.local/state/millennium-helpers/relaunch.env"

# No state file -> no-op, must not error and must not call runuser
rm -f "${MOCK_BIN}/runuser.calls"
rm -f "$expected_state_file"
out=$(relaunch_steam "relaunch-test-user-missing" 2>&1)
rc=$?
assert_success "$rc" "relaunch_steam exits 0 when no state file exists"
assert_equals "" "$out" "relaunch_steam produces no output when no state file exists (silent no-op)"

# With a state file present (native, non-flatpak) -> should invoke runuser with steam
mkdir -p "$(dirname "$expected_state_file")"
cat > "$expected_state_file" << EOF
export DISPLAY=':1'
export STEAM_ARGS="-foo -bar"
export WAS_FLATPAK='false'
EOF
mock_cmd "steam" 'exit 0'
rm -f "${MOCK_BIN}/runuser.calls"
relaunch_steam "$test_relaunch_user" > /tmp/relaunch_stdout.$$ 2>&1
relaunch_out=$(cat /tmp/relaunch_stdout.$$)
rm -f /tmp/relaunch_stdout.$$
assert_contains "$relaunch_out" "Relaunching Steam" "relaunch_steam announces relaunch when a state file exists"
assert_file_not_exists "$expected_state_file" "relaunch_steam removes the state file after use"
assert_file_exists "${MOCK_BIN}/runuser.calls" "relaunch_steam invokes runuser to relaunch native steam"
runuser_call=$(cat "${MOCK_BIN}/runuser.calls" 2>/dev/null || true)
assert_contains "$runuser_call" "$test_relaunch_user" "relaunch_steam's runuser call targets the correct user"
assert_contains "$runuser_call" "steam" "relaunch_steam's runuser call launches steam"
rm -f "${MOCK_BIN}/steam" "${MOCK_BIN}/runuser.calls"

# With WAS_FLATPAK=true -> should invoke flatpak run instead of steam
cat > "$expected_state_file" << EOF
export STEAM_ARGS=""
export WAS_FLATPAK='true'
EOF
rm -f "${MOCK_BIN}/runuser.calls"
relaunch_steam "$test_relaunch_user" > /dev/null 2>&1
runuser_call=$(cat "${MOCK_BIN}/runuser.calls" 2>/dev/null || true)
assert_contains "$runuser_call" "flatpak run com.valvesoftware.Steam" "relaunch_steam launches flatpak Steam when WAS_FLATPAK=true"
rm -f "${MOCK_BIN}/runuser.calls" "$expected_state_file"

# relaunch_steam must refuse to follow a symlink planted at the state file
# path (defense against a race that pre-dates directory lockdown).
ln -sf "/etc/hostname" "$expected_state_file"
symlink_out=$(relaunch_steam "$test_relaunch_user" 2>&1)
assert_equals "" "$symlink_out" "relaunch_steam silently refuses to source a symlinked state file"
assert_file_exists "$expected_state_file" "relaunch_steam does not delete an untrusted symlinked state file"
rm -f "$expected_state_file"

# --- capture_steam_env() ---

# No steam process running (pgrep mocked to find nothing) -> state file records WAS_FLATPAK=false only
mock_cmd "pgrep" 'exit 1'
mock_cmd "flatpak" 'exit 1'
rm -f "$expected_state_file"
capture_steam_env "$test_relaunch_user"
assert_file_exists "$expected_state_file" "capture_steam_env creates the state file even with no Steam process"
capture_dir_perms=$(stat -c '%a' "$(dirname "$expected_state_file")")
assert_equals "700" "$capture_dir_perms" "capture_steam_env locks the state directory down to mode 700"
capture_contents=$(cat "$expected_state_file")
assert_contains "$capture_contents" "WAS_FLATPAK='false'" "capture_steam_env records WAS_FLATPAK=false when Steam/Flatpak aren't running"
assert_not_contains "$capture_contents" "STEAM_ARGS" "capture_steam_env skips STEAM_ARGS when no Steam process is found"
rm -f "$expected_state_file" "${MOCK_BIN}/pgrep" "${MOCK_BIN}/flatpak"

# Steam process found -> should capture DISPLAY and STEAM_ARGS from /proc/<pid>/environ & cmdline
fake_pid=$$
mock_cmd "pgrep" "echo ${fake_pid}"
capture_steam_env "$test_relaunch_user"
assert_file_exists "$expected_state_file" "capture_steam_env creates state file when a Steam pid is found"
capture_contents2=$(cat "$expected_state_file")
assert_contains "$capture_contents2" "WAS_FLATPAK='false'" "capture_steam_env still records WAS_FLATPAK correctly when Steam is running"
assert_contains "$capture_contents2" "STEAM_ARGS=" "capture_steam_env records a STEAM_ARGS line when a Steam pid is found"
rm -f "$expected_state_file" "${MOCK_BIN}/pgrep"
rm -rf "$relaunch_test_home"
rm -f "${MOCK_BIN}/getent"

# --- close_steam_gracefully() ---

mock_cmd "getent" 'echo "closetest:x:1000:1000::/home/closetest:/bin/bash"'
mock_cmd "runuser" 'echo "runuser: $*" >> "'"${MOCK_BIN}"'/close_runuser.calls"; exit 0'
# Simulate Steam already gone by the time we poll for it (pgrep fails => loop exits immediately)
mock_cmd "pgrep" 'exit 1'
mock_cmd "steam" 'exit 0'
close_out=$(close_steam_gracefully "closetest" 2>&1)
assert_contains "$close_out" "Steam closed successfully" "close_steam_gracefully reports success once pgrep no longer finds steam"
close_calls=$(cat "${MOCK_BIN}/close_runuser.calls" 2>/dev/null || true)
assert_contains "$close_calls" "steam -shutdown" "close_steam_gracefully issues a native 'steam -shutdown' command via runuser"
rm -f "${MOCK_BIN}/close_runuser.calls" "${MOCK_BIN}/getent" "${MOCK_BIN}/runuser" "${MOCK_BIN}/pgrep" "${MOCK_BIN}/steam"

# --- send_notification() ---

# Root target user must be a strict no-op regardless of notify-send availability
mock_cmd "notify-send" 'echo "notify-send: $*" >> "'"${MOCK_BIN}"'/notify.calls"'
send_notification "Title" "Message" "root"
assert_file_not_exists "${MOCK_BIN}/notify.calls" "send_notification is a no-op for the root user"

# Non-root user with notify-send available -> should invoke it with title/message
# shellcheck disable=SC2016
mock_cmd "runuser" '
shift  # drop -l
target_user="$1"; shift
shift  # drop -c
eval "$1"
'
send_notification "Millennium Updated" "All good" "notify-test-user"
notify_calls=$(cat "${MOCK_BIN}/notify.calls" 2>/dev/null || true)
assert_contains "$notify_calls" "Millennium Updated" "send_notification passes the title through to notify-send"
assert_contains "$notify_calls" "All good" "send_notification passes the message through to notify-send"
rm -f "${MOCK_BIN}/notify.calls" "${MOCK_BIN}/notify-send" "${MOCK_BIN}/runuser"

# --- load_user_config() ---

# Setup a clean config environment
TEMP_CONF_DIR=$(mktemp -d)
OLD_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}"
export XDG_CONFIG_HOME="${TEMP_CONF_DIR}"

# 1. No config file -> nothing exported
unset GITHUB_TOKEN
unset CONFIG_UPDATE_CHANNEL
load_user_config
assert_equals "" "${GITHUB_TOKEN:-}" "load_user_config does not export GITHUB_TOKEN if no config exists"
assert_equals "" "${CONFIG_UPDATE_CHANNEL:-}" "load_user_config does not export CONFIG_UPDATE_CHANNEL if no config exists"

# 2. Config file exists -> variables loaded
mkdir -p "${TEMP_CONF_DIR}/millennium-helpers"
cat > "${TEMP_CONF_DIR}/millennium-helpers/config.json" << EOF
{
  "update_channel": "beta",
  "github_token": "token123"
}
EOF

load_user_config
assert_equals "token123" "${GITHUB_TOKEN:-}" "load_user_config loads and exports GITHUB_TOKEN from config.json"
assert_equals "beta" "${CONFIG_UPDATE_CHANNEL:-}" "load_user_config loads and exports CONFIG_UPDATE_CHANNEL from config.json"

# 3. Environment variables should NOT be overwritten if already set
export GITHUB_TOKEN="env_token"
export CONFIG_UPDATE_CHANNEL="env_channel"
load_user_config
assert_equals "env_token" "${GITHUB_TOKEN}" "load_user_config preserves existing GITHUB_TOKEN environment override"
assert_equals "env_channel" "${CONFIG_UPDATE_CHANNEL}" "load_user_config preserves existing CONFIG_UPDATE_CHANNEL environment override"

# Cleanup
unset GITHUB_TOKEN
unset CONFIG_UPDATE_CHANNEL
if [[ -n "$OLD_XDG_CONFIG_HOME" ]]; then
  export XDG_CONFIG_HOME="$OLD_XDG_CONFIG_HOME"
else
  unset XDG_CONFIG_HOME
fi
rm -rf "$TEMP_CONF_DIR"

print_summary

