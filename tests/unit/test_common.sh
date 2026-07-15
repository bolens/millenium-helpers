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

# --- install_millennium_license ---
if declare -F install_millennium_license >/dev/null; then
  _report true "install_millennium_license is defined"
else
  _report false "install_millennium_license is defined"
fi
if declare -F find_millennium_license_source >/dev/null; then
  _report true "find_millennium_license_source is defined"
else
  _report false "find_millennium_license_source is defined"
fi

lic_src="$(find_millennium_license_source)"
assert_contains "$lic_src" "MILLENNIUM-LICENSE.md" "find_millennium_license_source resolves vendored file"
assert_file_exists "$lic_src" "vendored Millennium license exists"

lic_dest="$(mktemp -d)"
install_millennium_license "$lic_dest"
assert_file_exists "${lic_dest}/LICENSE" "install_millennium_license writes LICENSE"
assert_contains "$(cat "${lic_dest}/LICENSE")" "Project Millennium" "installed LICENSE names Project Millennium"
assert_contains "$(cat "${lic_dest}/LICENSE")" "MIT License" "installed LICENSE is MIT"
rm -rf "$lic_dest"

print_summary
