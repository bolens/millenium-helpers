#!/usr/bin/env bash
# Unit tests for scripts/common.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

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
marker_file=$(mktemp 2>/dev/null || mktemp -t tmp.XXXXXX)
execute touch "$marker_file.executed"
assert_file_exists "${marker_file}.executed" "execute (live) actually runs the given command"
rm -f "$marker_file" "${marker_file}.executed"

DRY_RUN=true
# --- write_file() ---

target_file=$(mktemp -u 2>/dev/null || mktemp -u -t tmp.XXXXXX)
out=$(echo "file contents" | write_file "$target_file")
assert_contains "$out" "[DRY RUN]" "write_file (dry-run) prints DRY RUN marker"
assert_contains "$out" "$target_file" "write_file (dry-run) mentions target path"
assert_file_not_exists "$target_file" "write_file (dry-run) does not create the file"

DRY_RUN=false
target_file2=$(mktemp -u 2>/dev/null || mktemp -u -t tmp.XXXXXX)
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

# --- portable_realpath_m() ---

test_dir_temp=$(mktemp -d)
resolved_dir=$(portable_realpath_m "$test_dir_temp")
expected_dir=$(cd "$test_dir_temp" && pwd -P)
assert_equals "$expected_dir" "$resolved_dir" "portable_realpath_m resolves existing directory correctly"

resolved_nonexistent=$(portable_realpath_m "${test_dir_temp}/nonexistent_file")
assert_equals "${expected_dir}/nonexistent_file" "$resolved_nonexistent" "portable_realpath_m resolves non-existent file path correctly"

resolved_parent_traversal=$(portable_realpath_m "${test_dir_temp}/subfolder/../another_file")
assert_equals "${expected_dir}/another_file" "$resolved_parent_traversal" "portable_realpath_m resolves path containing parent traversal components correctly"

rm -rf "$test_dir_temp"

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

# Mock uname to return Linux during Steam tests to test Linux code paths portably
mock_cmd "uname" 'echo "Linux"'

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
rm -f "${MOCK_BIN}/runuser.calls"
# Keep the default steam mock; never leave PATH pointing at the real client.
mock_cmd "steam" 'exit 0'

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

# Even with the runuser mock deleted, TEST_SUITE_RUN must still prevent a
# real steam launch (regression for the ordering bug where MOCK_BIN alone
# was treated as "safe to runuser" and then fell through to eval).
cat > "$expected_state_file" << EOF
export DISPLAY=':1'
export STEAM_ARGS=""
export WAS_FLATPAK='false'
EOF
mock_cmd "steam" 'echo "REAL_STEAM_INVOKED $*" >> "'"${MOCK_BIN}"'/steam.calls"; exit 0'
rm -f "${MOCK_BIN}/runuser" "${MOCK_BIN}/runuser.calls" "${MOCK_BIN}/steam.calls"
bypass_out=$(relaunch_steam "$test_relaunch_user" 2>&1)
assert_contains "$bypass_out" "[TEST] Bypassing" "relaunch_steam bypasses host Steam when runuser mock is missing under TEST_SUITE_RUN"
assert_file_not_exists "${MOCK_BIN}/steam.calls" "relaunch_steam does not invoke steam when bypassing under TEST_SUITE_RUN"
mock_cmd "runuser" 'echo "runuser called: $*" >> "'"${MOCK_BIN}"'/runuser.calls"'
mock_cmd "steam" 'exit 0'

# relaunch_steam must refuse to follow a symlink planted at the state file
# path (defense against a race that pre-dates directory lockdown).
ln -sf "/etc/hosts" "$expected_state_file"
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
capture_dir_perms=$(get_file_perms "$(dirname "$expected_state_file")")
assert_equals "700" "$capture_dir_perms" "capture_steam_env locks the state directory down to mode 700"
capture_contents=$(cat "$expected_state_file")
assert_contains "$capture_contents" "WAS_FLATPAK='false'" "capture_steam_env records WAS_FLATPAK=false when Steam/Flatpak aren't running"
assert_not_contains "$capture_contents" "STEAM_ARGS" "capture_steam_env skips STEAM_ARGS when no Steam process is found"
rm -f "$expected_state_file" "${MOCK_BIN}/flatpak"
mock_cmd "pgrep" 'exit 1'

# Steam process found -> capture DISPLAY/STEAM_ARGS from MOCK_PROC, never host /proc
fake_pid=424242
MOCK_PROC=$(mktemp -d)
export MOCK_PROC
mkdir -p "${MOCK_PROC}/${fake_pid}"
printf 'DISPLAY=:99\0STEAM_ARGS=\0' > "${MOCK_PROC}/${fake_pid}/environ"
printf 'steam\0-silent\0' > "${MOCK_PROC}/${fake_pid}/cmdline"
mock_cmd "pgrep" "echo ${fake_pid}"
capture_steam_env "$test_relaunch_user"
assert_file_exists "$expected_state_file" "capture_steam_env creates state file when a Steam pid is found"
capture_contents2=$(cat "$expected_state_file")
assert_contains "$capture_contents2" "WAS_FLATPAK='false'" "capture_steam_env still records WAS_FLATPAK correctly when Steam is running"
assert_contains "$capture_contents2" "STEAM_ARGS=" "capture_steam_env records a STEAM_ARGS line when a Steam pid is found"
assert_contains "$capture_contents2" "DISPLAY=':99'" "capture_steam_env reads DISPLAY from MOCK_PROC, not host /proc"
rm -f "$expected_state_file"
rm -rf "$MOCK_PROC"
export MOCK_PROC="/nonexistent_mock_proc"
mock_cmd "pgrep" 'exit 1'
rm -rf "$relaunch_test_home"
rm -f "${MOCK_BIN}/getent"
mock_cmd "getent" 'exit 1'

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
rm -f "${MOCK_BIN}/close_runuser.calls" "${MOCK_BIN}/getent"
# Restore host-protection defaults after this section's custom mocks
mock_cmd "runuser" 'exit 0'
mock_cmd "pgrep" 'exit 1'
mock_cmd "steam" 'exit 0'

# --- confirm_close_steam() ---

mock_cmd "getent" 'echo "closetest:x:1000:1000::/home/closetest:/bin/bash"'
mock_cmd "runuser" 'echo "runuser: $*" >> "'"${MOCK_BIN}"'/confirm_close.calls"; exit 0'
mock_cmd "pgrep" 'exit 1'
mock_cmd "steam" 'exit 0'

# ASSUME_YES / explicit true skips the prompt and closes
confirm_out=$(confirm_close_steam "closetest" "true" 2>&1)
rc=$?
assert_success "$rc" "confirm_close_steam with assume_yes=true exits 0"
assert_contains "$confirm_out" "Steam closed successfully" "confirm_close_steam with assume_yes=true closes Steam"

# Non-interactive stdin (not a TTY) auto-confirms even without TEST_SUITE_RUN
saved_test_suite="${TEST_SUITE_RUN:-}"
unset TEST_SUITE_RUN
confirm_out=$(confirm_close_steam "closetest" "false" </dev/null 2>&1)
rc=$?
assert_success "$rc" "confirm_close_steam non-interactive auto-confirms and exits 0"
assert_contains "$confirm_out" "Steam closed successfully" "confirm_close_steam non-interactive closes Steam"
if [[ -n "$saved_test_suite" ]]; then
  export TEST_SUITE_RUN="$saved_test_suite"
else
  export TEST_SUITE_RUN=true
fi

# Interactive decline: force the prompt path without requiring a PTY
# (CI/sandboxes often cannot allocate pty devices).
saved_test_suite="${TEST_SUITE_RUN:-}"
unset TEST_SUITE_RUN
confirm_out=$(
  printf 'n\n' | CONFIRM_CLOSE_FORCE_PROMPT=1 confirm_close_steam closetest false 2>&1
  echo "CONFIRM_RC=$?"
)
if [[ -n "$saved_test_suite" ]]; then
  export TEST_SUITE_RUN="$saved_test_suite"
else
  export TEST_SUITE_RUN=true
fi
confirm_flat=$(printf '%s' "$confirm_out" | tr -d '\r')
assert_contains "$confirm_flat" "CONFIRM_RC=1" "confirm_close_steam declines when user answers n on a TTY"
assert_contains "$confirm_flat" "Aborted" "confirm_close_steam decline message mentions Aborted"
assert_not_contains "$confirm_flat" "Steam closed successfully" "confirm_close_steam decline does not close Steam"

# Also accept "y" on the forced-prompt path
unset TEST_SUITE_RUN
confirm_out=$(
  printf 'y\n' | CONFIRM_CLOSE_FORCE_PROMPT=1 confirm_close_steam closetest false 2>&1
  echo "CONFIRM_RC=$?"
)
export TEST_SUITE_RUN=true
confirm_flat=$(printf '%s' "$confirm_out" | tr -d '\r')
assert_contains "$confirm_flat" "CONFIRM_RC=0" "confirm_close_steam accepts y on forced prompt"
assert_contains "$confirm_flat" "Steam closed successfully" "confirm_close_steam forced-prompt yes closes Steam"
rm -f "${MOCK_BIN}/confirm_close.calls" "${MOCK_BIN}/getent"
mock_cmd "runuser" 'exit 0'
mock_cmd "pgrep" 'exit 1'
mock_cmd "steam" 'exit 0'

# --- print_diag_next_steps() ---

# shellcheck source=../../scripts/lib/diag.sh
source "${REPO_ROOT}/scripts/lib/diag.sh"

# Flags are read as globals inside print_diag_next_steps (not lexical locals).
next_out=$(
  BINARIES_OK=true HOOKS_OK=true FLATPAK_OK=true PERMISSIONS_OK=true SKINS_DIR_OK=true \
  SUDOERS_OK=true TIMER_ACTIVE=true LINGER_OK=true SCRIPTS_UP_TO_DATE=true \
  COMPLETIONS_OK=true CLEAN_OF_OBSOLETE=true RUNNING_USER=testuser \
  print_diag_next_steps 2>&1
)
assert_contains "$next_out" "No issues detected" "print_diag_next_steps reports healthy when all flags are ok"
assert_contains "$next_out" "millennium schedule status" "print_diag_next_steps healthy tip mentions schedule status"

next_out=$(
  BINARIES_OK=false HOOKS_OK=false FLATPAK_OK=true PERMISSIONS_OK=true SKINS_DIR_OK=true \
  SUDOERS_OK=true TIMER_ACTIVE=false LINGER_OK=true SCRIPTS_UP_TO_DATE=true \
  COMPLETIONS_OK=true CLEAN_OF_OBSOLETE=true RUNNING_USER=testuser \
  print_diag_next_steps 2>&1
)
assert_contains "$next_out" "issue(s) detected" "print_diag_next_steps reports issue count when flags fail"
assert_contains "$next_out" "millennium doctor" "print_diag_next_steps suggests doctor"
assert_contains "$next_out" "millennium upgrade" "print_diag_next_steps suggests upgrade for bad binaries"
assert_contains "$next_out" "millennium schedule enable" "print_diag_next_steps suggests enabling the scheduler"

# --- print_upgrade_failure_tips() ---
fail_tips=$(print_upgrade_failure_tips 42 2>&1)
assert_contains "$fail_tips" "Upgrade failed" "print_upgrade_failure_tips mentions failure"
assert_contains "$fail_tips" "exit code: 42" "print_upgrade_failure_tips includes exit code"
assert_contains "$fail_tips" "millennium upgrade --rollback list" "print_upgrade_failure_tips suggests rollback list"
assert_contains "$fail_tips" "millennium diag" "print_upgrade_failure_tips suggests diag"
assert_contains "$fail_tips" "--yes" "print_upgrade_failure_tips mentions --yes"

# --- quiet mode (log_info) ---
export QUIET=true
quiet_out=$(log_info "should-be-silent" 2>&1)
assert_equals "" "$quiet_out" "log_info is silent when QUIET=true"
export QUIET=false
export MILLENNIUM_QUIET=1
quiet_out=$(log_info "should-be-silent-env" 2>&1)
assert_equals "" "$quiet_out" "log_info is silent when MILLENNIUM_QUIET is set"
unset MILLENNIUM_QUIET
warn_out=$(log_warn "still-warns" 2>&1)
assert_contains "$warn_out" "still-warns" "log_warn still prints under quiet-capable logging"
err_out=$(log_error "still-errors" 2>&1)
assert_contains "$err_out" "still-errors" "log_error still prints under quiet-capable logging"

# --- suggest_closest() ---
assert_equals "list" "$(suggest_closest lst list install update remove)" "suggest_closest maps lst to list"
assert_equals "status" "$(suggest_closest stauts enable disable status setup)" "suggest_closest maps stauts to status"
assert_equals "" "$(suggest_closest zzzz list install || true)" "suggest_closest returns empty for unrelated input"

# --- print_game_running_tip() ---
game_tip=$(print_game_running_tip "upgrade" 2>&1)
assert_contains "$game_tip" "Close the running game" "print_game_running_tip tells user to close the game"
assert_contains "$game_tip" "--yes" "print_game_running_tip mentions --yes"

# --- _github_explain_http_error() ---

err_out=$(_github_explain_http_error "401" 2>&1)
assert_contains "$err_out" "401" "_github_explain_http_error mentions HTTP 401"
assert_contains "$err_out" "millennium schedule setup" "_github_explain_http_error 401 tip points at schedule setup"

err_hdr=$(mktemp 2>/dev/null || mktemp -t mh-hdr.XXXXXX)
printf 'x-ratelimit-remaining: 0\nx-ratelimit-reset: 9999999999\n' > "$err_hdr"
err_out=$(_github_explain_http_error "403" "$err_hdr" 2>&1)
assert_contains "$err_out" "rate limit" "_github_explain_http_error 403 with remaining=0 mentions rate limit"
assert_contains "$err_out" "github_token" "_github_explain_http_error 403 tip mentions github_token"
rm -f "$err_hdr"

err_out=$(_github_explain_http_error "404" 2>&1)
assert_contains "$err_out" "404" "_github_explain_http_error mentions HTTP 404"

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
rm -f "${MOCK_BIN}/notify.calls" "${MOCK_BIN}/notify-send"
mock_cmd "runuser" 'exit 0'
mock_cmd "notify-send" 'exit 0'
unmock_cmd "uname"

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

# --- download_file() ---

# 1. Dry run mode
out=$(DRY_RUN=true download_file "https://example.com/file" "/tmp/dest" 2>&1)
assert_contains "$out" "Would download" "download_file (dry-run) prints dry run notice"
assert_contains "$out" "https://example.com/file" "download_file (dry-run) contains source url"
assert_contains "$out" "/tmp/dest" "download_file (dry-run) contains destination path"

# 2. Live download (mocked curl)
# We have setup_mock_bin already active, so we can mock curl
# shellcheck disable=SC2016
mock_cmd "curl" '
# Mock curl that writes mock file and returns success
dest=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    shift
    dest="$1"
  fi
  shift
done
echo "mock download content" > "$dest"
exit 0
'
download_temp=$(mktemp 2>/dev/null || mktemp -t tmp.XXXXXX)
out=$(DRY_RUN=false download_file "https://example.com/file" "$download_temp" "Fetching file" 2>&1)
rc=$?
assert_success "$rc" "download_file returns 0 on successful curl"
assert_contains "$out" "Fetching file" "download_file outputs the description message"
assert_contains "$out" "OK" "download_file outputs OK on success"
assert_file_exists "$download_temp" "download_file actually writes the target file"
assert_equals "mock download content" "$(cat "$download_temp")" "downloaded file content matches mock"
rm -f "$download_temp"

# 3. Live download failure (mocked curl exit 1)
mock_cmd "curl" '
echo "curl error message" >&2
exit 1
'
download_temp=$(mktemp 2>/dev/null || mktemp -t tmp.XXXXXX)
out=$(DRY_RUN=false download_file "https://example.com/file" "$download_temp" "Fetching file" 2>&1)
rc=$?
assert_failure "$rc" "download_file returns non-zero on curl failure"
assert_contains "$out" "FAIL" "download_file outputs FAIL on failure"
assert_contains "$out" "curl error message" "download_file outputs curl stderr logs to stderr"
rm -f "$download_temp"

# --- get_user_home() ---

# 1. Resolve home using getent (Linux standard path)
mock_cmd "getent" '
if [[ "$*" == *"passwd testuser"* ]]; then
  echo "testuser:x:1000:1000::/mock/getent/home:/bin/bash"
  exit 0
fi
exit 1
'
home_dir=$(get_user_home "testuser")
assert_equals "/mock/getent/home" "$home_dir" "get_user_home resolves home using getent"
unmock_cmd "getent"

# 2. Resolve home using dscl (macOS standard path)
mock_cmd "getent" "exit 1"
mock_cmd "dscl" '
if [[ "$*" == *". -read /Users/testuser NFSHomeDirectory"* ]]; then
  echo "NFSHomeDirectory: /mock/dscl/home"
  exit 0
fi
exit 1
'
home_dir=$(get_user_home "testuser")
assert_equals "/mock/dscl/home" "$home_dir" "get_user_home resolves home using dscl on macOS"
unmock_cmd "getent"
unmock_cmd "dscl"

# 3. Fallback path using shell tilde expansion.
# Compare against tilde expansion for the same user — $HOME can diverge
# (e.g. root with HOME inherited from sudo/SUDO_USER).
mock_cmd "getent" "exit 1"
mock_cmd "dscl" "exit 1"
current_user=$(id -un)
expected_home=$(eval echo "~${current_user}")
home_dir=$(get_user_home "$current_user")
assert_equals "$expected_home" "$home_dir" "get_user_home falls back to tilde expansion"
unmock_cmd "getent"
unmock_cmd "dscl"

# --- get_helpers_version / print_helpers_version ---

ver=$(get_helpers_version)
assert_equals "$EXPECTED_VERSION" "$ver" "get_helpers_version reads the repo VERSION file"

out=$(print_helpers_version)
assert_contains "$out" "$EXPECTED_VERSION" "print_helpers_version includes the version number"
assert_contains "$out" "$(basename "$0")" "print_helpers_version includes the invoking script name"

# Isolated VERSION file: copy version.sh into a temp tree with its own VERSION
ver_tmp=$(mktemp -d)
mkdir -p "${ver_tmp}/scripts/lib"
cp "${REPO_ROOT}/scripts/lib/version.sh" "${ver_tmp}/scripts/lib/version.sh"
echo "7.7.7" > "${ver_tmp}/VERSION"
ver_isolated=$(
  bash -c 'source "'"${ver_tmp}"'/scripts/lib/version.sh"; get_helpers_version'
)
assert_equals "7.7.7" "$ver_isolated" "get_helpers_version prefers VERSION next to the sourced lib tree"
rm -rf "$ver_tmp"

# --- NO_COLOR disables ANSI escapes in logging helpers ---

# shellcheck disable=SC2016
no_color_out=$(
  NO_COLOR=1 bash -c '
    source "'"${REPO_ROOT}"'/scripts/lib/logging.sh"
    printf "%s" "${RED}${GREEN}${YELLOW}${BLUE}${NC}"
  '
)
assert_equals "" "$no_color_out" "NO_COLOR clears ANSI color variables in logging.sh"

# shellcheck disable=SC2016
force_color_out=$(
  env -u NO_COLOR FORCE_COLOR=1 bash -c '
    source "'"${REPO_ROOT}"'/scripts/lib/logging.sh"
    printf "%s" "${GREEN}"
  '
)
assert_not_equals "" "$force_color_out" "FORCE_COLOR enables ANSI color variables in logging.sh"

# --- print_diag_item (diag.sh) ---

# shellcheck disable=SC2016
diag_out=$(
  NO_COLOR=1 bash -c '
    source "'"${REPO_ROOT}"'/scripts/lib/logging.sh"
    source "'"${REPO_ROOT}"'/scripts/lib/diag.sh"
    print_diag_item "ok" "Steam Client" "Running"
    print_diag_item "warn" "Hooks" "Missing"
    print_diag_item "error" "Binaries" "Corrupted"
  '
)
assert_contains "$diag_out" "Steam Client" "print_diag_item ok includes the label"
assert_contains "$diag_out" "Running" "print_diag_item ok includes the value"
assert_contains "$diag_out" "Hooks" "print_diag_item warn includes the label"
assert_contains "$diag_out" "Binaries" "print_diag_item error includes the label"
assert_contains "$diag_out" "✔" "print_diag_item ok uses the check mark"
assert_contains "$diag_out" "!" "print_diag_item warn uses the bang marker"
assert_contains "$diag_out" "✘" "print_diag_item error uses the cross mark"

diag_ascii=$(
  NO_COLOR=1 NO_UNICODE=1 bash -c '
    source "'"${REPO_ROOT}"'/scripts/lib/logging.sh"
    source "'"${REPO_ROOT}"'/scripts/lib/diag.sh"
    print_diag_item "ok" "Steam Client" "Running"
    print_diag_item "warn" "Hooks" "Missing"
    print_diag_item "error" "Binaries" "Corrupted"
  '
)
assert_contains "$diag_ascii" "OK" "print_diag_item ok uses ASCII OK when NO_UNICODE=1"
assert_contains "$diag_ascii" "WARN" "print_diag_item warn uses ASCII WARN when NO_UNICODE=1"
assert_contains "$diag_ascii" "FAIL" "print_diag_item error uses ASCII FAIL when NO_UNICODE=1"

# --- prune_backups age-prunes the last remaining backup without unbound-array abort ---
# Bash 3.2 (macOS) treats empty "${arr[@]}" as unbound under set -u; pruning the
# final backup used to reassign sorted_backups from an empty temp array and die.

PRUNE_LIB=$(mktemp -d 2>/dev/null || mktemp -d -t prune.XXXXXX)
mkdir -p "${PRUNE_LIB}/millennium.bak_v1.0.0"
# Make the backup look old enough to age out (mtime ~ 10 days ago).
if touch -d "10 days ago" "${PRUNE_LIB}/millennium.bak_v1.0.0" 2>/dev/null; then
  :
elif touch -t "$(date -v-10d +%Y%m%d%H%M.%S)" "${PRUNE_LIB}/millennium.bak_v1.0.0" 2>/dev/null; then
  :
else
  # Last resort: set mtime via python for exotic environments.
  python3 -c "import os, time; os.utime('${PRUNE_LIB}/millennium.bak_v1.0.0', (time.time()-10*86400, time.time()-10*86400))"
fi
export MOCK_LIB_DIR="$PRUNE_LIB"
export DRY_RUN=false
out=$(prune_backups 5 1 2>&1)
rc=$?
assert_success "$rc" "prune_backups age-prunes the last backup without aborting"
assert_contains "$out" "Removed old backup" "prune_backups reports removal of the aged-out backup"
assert_file_not_exists "${PRUNE_LIB}/millennium.bak_v1.0.0" "prune_backups deletes the aged-out backup directory"
unset MOCK_LIB_DIR
export DRY_RUN=true
rm -rf "$PRUNE_LIB"

# --- sysctl_user() ---
#
# Direct path: non-root, or root targeting root → bare `systemctl --user`.
# Machine path: root targeting another user → `systemctl --user -M user@.host`.
# Fallback: machine bus unreachable → runuser with XDG_RUNTIME_DIR set.

# 1) Direct path (this process's user / root→root)
unset RUNNING_USER SUDO_USER
mock_cmd "systemctl" 'echo "systemctl: $*"; exit 0'
out=$(sysctl_user daemon-reload 2>&1)
rc=$?
assert_success "$rc" "sysctl_user daemon-reload exits 0 on direct path"
assert_contains "$out" "systemctl: --user daemon-reload" "sysctl_user direct path invokes systemctl --user"
assert_not_contains "$out" "-M" "sysctl_user direct path does not use --machine"

mock_cmd "systemctl" 'echo "disabled"; exit 1'
out=$(sysctl_user is-enabled millennium-update.timer 2>&1)
rc=$?
assert_failure "$rc" "sysctl_user preserves non-zero exit from systemctl is-enabled"
assert_contains "$out" "disabled" "sysctl_user surfaces systemctl is-enabled output"

# 2–6) Root → other user. CI runners are not root, so fake euid 0 via id.
# shellcheck disable=SC2016 # mock body must stay single-quoted so vars expand at runtime
mock_cmd "id" '
if [[ "$1" == "-u" && $# -eq 1 ]]; then
  echo "0"
  exit 0
fi
if [[ "$1" == "-u" && "$2" == "alice" ]]; then
  echo "4242"
  exit 0
fi
if [[ "$1" == "-u" && "$2" == "bob" ]]; then
  echo "4243"
  exit 0
fi
exec /usr/bin/id "$@"
'

# 2) Root → other user: prefer --machine=user@.host
export RUNNING_USER="alice"
mock_cmd "systemctl" '
echo "systemctl: $*" >> "'"${MOCK_BIN}"'/systemctl.calls"
if [[ "$*" == *"-M alice@.host"* ]]; then
  echo "active"
  exit 0
fi
echo "unexpected: $*" >&2
exit 99
'
rm -f "${MOCK_BIN}/systemctl.calls" "${MOCK_BIN}/runuser.calls"
mock_cmd "runuser" 'echo "runuser: $*" >> "'"${MOCK_BIN}"'/runuser.calls"; exit 0'
out=$(sysctl_user is-active millennium-update.timer 2>&1)
rc=$?
assert_success "$rc" "sysctl_user root→user succeeds via --machine"
assert_contains "$out" "active" "sysctl_user --machine path returns systemctl output"
calls=$(cat "${MOCK_BIN}/systemctl.calls" 2>/dev/null || true)
assert_contains "$calls" "--user -M alice@.host is-active millennium-update.timer" \
  "sysctl_user root→user invokes systemctl --user -M alice@.host"
assert_file_not_exists "${MOCK_BIN}/runuser.calls" \
  "sysctl_user does not fall back to runuser when --machine succeeds"

# 3) --machine returns a real failure (disabled): must NOT treat as bus error
mock_cmd "systemctl" '
echo "systemctl: $*" >> "'"${MOCK_BIN}"'/systemctl.calls"
if [[ "$*" == *"-M alice@.host"* ]]; then
  echo "disabled"
  exit 1
fi
exit 99
'
rm -f "${MOCK_BIN}/systemctl.calls" "${MOCK_BIN}/runuser.calls"
mock_cmd "runuser" 'echo "runuser: $*" >> "'"${MOCK_BIN}"'/runuser.calls"; exit 0'
out=$(sysctl_user is-enabled millennium-update.timer 2>&1)
rc=$?
assert_failure "$rc" "sysctl_user preserves is-enabled failure via --machine"
assert_contains "$out" "disabled" "sysctl_user returns disabled from --machine path"
assert_file_not_exists "${MOCK_BIN}/runuser.calls" \
  "sysctl_user does not fall back to runuser on ordinary is-enabled failure"

# 4) --machine bus unreachable + no runtime dir → clear error (no runuser)
# shellcheck disable=SC2016 # mock body must stay single-quoted so vars expand at runtime
mock_cmd "systemctl" '
echo "Failed to connect to user scope bus via local transport: \$DBUS_SESSION_BUS_ADDRESS and \$XDG_RUNTIME_DIR not defined" >&2
exit 1
'
rm -f "${MOCK_BIN}/runuser.calls"
mock_cmd "runuser" 'echo "runuser: $*" >> "'"${MOCK_BIN}"'/runuser.calls"; exit 0'
unset MILLENNIUM_USER_RUNTIME_ROOT
out=$(sysctl_user daemon-reload 2>&1)
rc=$?
assert_failure "$rc" "sysctl_user fails when user session runtime dir is missing"
assert_contains "$out" "no user session for 'alice'" "sysctl_user reports missing user session"
assert_contains "$out" "enable-linger" "sysctl_user suggests enabling linger"
assert_file_not_exists "${MOCK_BIN}/runuser.calls" \
  "sysctl_user does not call runuser when runtime dir is missing"

# 5) --machine bus unreachable + runtime dir present → runuser fallback
fake_runtime=$(mktemp -d)
mkdir -p "${fake_runtime}/4242"
export MILLENNIUM_USER_RUNTIME_ROOT="$fake_runtime"
mock_cmd "systemctl" '
# First invocation is the --machine attempt (captured via command substitution).
if [[ "$*" == *"-M"* ]]; then
  echo "Failed to connect to bus: Connection refused" >&2
  exit 1
fi
# Invoked inside runuser fallback
echo "systemctl-via-runuser: $*"
exit 0
'
rm -f "${MOCK_BIN}/runuser.calls"
mock_cmd "runuser" '
echo "runuser: $*" >> "'"${MOCK_BIN}"'/runuser.calls"
# Execute the remaining command (env … systemctl …) so the fallback is real
shift  # -u
shift  # alice
shift  # --
exec "$@"
'
out=$(sysctl_user daemon-reload 2>&1)
rc=$?
assert_success "$rc" "sysctl_user succeeds via runuser fallback when --machine bus is down"
assert_contains "$out" "systemctl-via-runuser: --user daemon-reload" \
  "sysctl_user runuser fallback runs systemctl --user"
runuser_call=$(cat "${MOCK_BIN}/runuser.calls" 2>/dev/null || true)
assert_contains "$runuser_call" "-u alice" "sysctl_user runuser targets alice"
assert_contains "$runuser_call" "XDG_RUNTIME_DIR=${fake_runtime}/4242" \
  "sysctl_user runuser sets XDG_RUNTIME_DIR for alice"
assert_contains "$runuser_call" "DBUS_SESSION_BUS_ADDRESS=unix:path=${fake_runtime}/4242/bus" \
  "sysctl_user runuser sets DBUS_SESSION_BUS_ADDRESS for alice"

# 6) SUDO_USER is honored when RUNNING_USER is unset (sudo install/uninstall path)
unset RUNNING_USER
export SUDO_USER="bob"
mock_cmd "systemctl" '
echo "systemctl: $*" >> "'"${MOCK_BIN}"'/systemctl.calls"
if [[ "$*" == *"-M bob@.host"* ]]; then
  exit 0
fi
exit 99
'
rm -f "${MOCK_BIN}/systemctl.calls"
out=$(sysctl_user daemon-reload 2>&1)
rc=$?
assert_success "$rc" "sysctl_user uses SUDO_USER when RUNNING_USER is unset"
calls=$(cat "${MOCK_BIN}/systemctl.calls" 2>/dev/null || true)
assert_contains "$calls" "-M bob@.host" "sysctl_user --machine targets SUDO_USER"

# Cleanup sysctl_user test state
unset RUNNING_USER SUDO_USER MILLENNIUM_USER_RUNTIME_ROOT
rm -rf "$fake_runtime"
unmock_cmd "id"
unmock_cmd "systemctl"
unmock_cmd "runuser"
mock_cmd "systemctl" "exit 0"
mock_cmd "runuser" "exit 0"

print_summary

