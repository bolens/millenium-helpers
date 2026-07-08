#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-schedule.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

SCHEDULE_SH="${REPO_ROOT}/scripts/millennium-schedule.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

# Isolate systemd user unit files and state dir in a throwaway HOME/XDG dir
FAKE_XDG_CONFIG=$(mktemp -d)
export XDG_CONFIG_HOME="$FAKE_XDG_CONFIG"

# millennium-schedule.sh stores the Steam relaunch state file under the
# running user's home directory (resolved via getent), not /tmp. Point
# getent's reported home at a throwaway temp dir so post-update tests don't
# read/write the real developer $HOME.
FAKE_RELAUNCH_HOME=$(mktemp -d)
mock_cmd "getent" 'echo "faketestuser:x:1000:1000::'"${FAKE_RELAUNCH_HOME}"':/bin/bash"'
EXPECTED_STATE_FILE="${FAKE_RELAUNCH_HOME}/.local/state/millennium-helpers/relaunch.env"

# Fast stand-ins for the other helper scripts (avoid invoking real, slow tools)
mock_cmd "millennium-diag" 'exit 0'
mock_cmd "millennium-theme" 'exit 0'
mock_cmd "millennium-upgrade" 'exit 0'

run_schedule() {
  bash "$SCHEDULE_SH" "$@"
}

echo -e "${YELLOW}=== Behavioral tests: millennium-schedule.sh ===${NC}"

# --- Help / usage ---

out=$(run_schedule --help 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule --help exits 0"
assert_contains "$out" "enable" "millennium-schedule --help documents the enable command"
assert_contains "$out" "disable" "millennium-schedule --help documents the disable command"
assert_contains "$out" "status" "millennium-schedule --help documents the status command"

out=$(run_schedule 2>&1)
rc=$?
assert_failure "$rc" "millennium-schedule with no command exits non-zero"
assert_contains "$out" "Usage:" "millennium-schedule with no command prints usage"

# --- Invalid channel argument ---

out=$(run_schedule enable bogus-channel --dry-run 2>&1)
rc=$?
assert_failure "$rc" "millennium-schedule enable rejects an unrecognized channel argument"
assert_contains "$out" "Unknown option" "millennium-schedule enable reports the unrecognized channel as an unknown option"

# --- enable (no --cron flag): path depends on whether systemd is actually
# booted on this machine (millennium-schedule.sh auto-detects via
# /run/systemd/system and silently falls back to cron otherwise, e.g. inside
# minimal containers used in CI). Branch on the real environment so the test
# is accurate either way instead of assuming systemd is always available.

out=$(run_schedule enable stable --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule enable stable --dry-run exits 0"
assert_contains "$out" "DRY RUN" "millennium-schedule enable --dry-run announces dry-run mode"
if [[ -d /run/systemd/system ]]; then
  assert_contains "$out" "systemd user service file" "millennium-schedule enable --dry-run mentions creating the systemd service file"
  assert_file_not_exists "${FAKE_XDG_CONFIG}/systemd/user/millennium-update.timer" "millennium-schedule enable --dry-run does not actually write the timer unit file"
  assert_file_not_exists "${FAKE_XDG_CONFIG}/systemd/user/millennium-update.service" "millennium-schedule enable --dry-run does not actually write the service unit file"
else
  assert_contains "$out" "crontab" "millennium-schedule enable --dry-run falls back to crontab when systemd is not booted"
fi

# --- enable (cron path) dry-run ---

out=$(run_schedule enable beta --cron --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule enable beta --cron --dry-run exits 0"
assert_contains "$out" "DRY RUN" "millennium-schedule enable --cron --dry-run announces dry-run mode"
assert_contains "$out" "crontab" "millennium-schedule enable --cron --dry-run mentions crontab"
assert_contains "$out" "millennium-upgrade" "millennium-schedule enable beta --cron --dry-run references the upgrade script"

# --- disable dry-run ---

out=$(run_schedule disable --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule disable --dry-run exits 0"
assert_contains "$out" "DRY RUN" "millennium-schedule disable --dry-run announces dry-run mode"

# --- status (no timer/service configured) ---

out=$(run_schedule status 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule status exits 0 when nothing is configured"
assert_contains "$out" "not installed/configured" "millennium-schedule status reports the timer as unconfigured"

# --- pre-update: Steam not running ---

mock_cmd "pgrep" 'exit 1'
out=$(run_schedule pre-update 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule pre-update exits 0 when Steam isn't running"
assert_contains "$out" "not running" "millennium-schedule pre-update reports that Steam is not running"
rm -f "${MOCK_BIN}/pgrep"

# --- post-update: no saved relaunch state ---

rm -f "$EXPECTED_STATE_FILE"
out=$(run_schedule post-update 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule post-update exits 0 with no saved relaunch state (diag mocked to pass)"
assert_contains "$out" "No saved relaunch state" "millennium-schedule post-update reports no relaunch state was found"

# --- post-update: diagnostics failure aborts relaunch ---

mock_cmd "millennium-diag" 'exit 1'
out=$(run_schedule post-update 2>&1)
rc=$?
assert_failure "$rc" "millennium-schedule post-update exits non-zero when diagnostics fail"
assert_contains "$out" "failed verification" "millennium-schedule post-update explains the verification failure"
mock_cmd "millennium-diag" 'exit 0'

# --- Default channel selection from CONFIG_UPDATE_CHANNEL ---

export CONFIG_UPDATE_CHANNEL="beta"
out=$(run_schedule enable --dry-run --cron 2>&1)
assert_contains "$out" "millennium-upgrade" "millennium-schedule defaults to beta channel when CONFIG_UPDATE_CHANNEL is set to beta"
unset CONFIG_UPDATE_CHANNEL

# --- config command tests ---

export XDG_CONFIG_HOME="${FAKE_XDG_CONFIG}"

# 1. config list (default/empty)
out=$(run_schedule config list 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule config list exits 0"
assert_contains "$out" "update_channel" "config list lists update_channel"
assert_contains "$out" "github_token" "config list lists github_token"

# 2. config set update_channel
out=$(run_schedule config set update_channel beta 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule config set update_channel beta exits 0"
assert_contains "$out" "successfully" "config set confirms success"

# 3. config get update_channel
out=$(run_schedule config get update_channel 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule config get update_channel exits 0"
assert_equals "beta" "$(echo "$out" | tr -d '[:space:]')" "config get update_channel returns correct value"

# 4. config set validation failure
out=$(run_schedule config set update_channel invalid_val 2>&1)
rc=$?
assert_failure "$rc" "config set update_channel with invalid value fails"
assert_contains "$out" "must be 'stable' or 'beta'" "config set prints validation error"

# 5. config set backup_limit
out=$(run_schedule config set backup_limit 10 2>&1)
rc=$?
assert_success "$rc" "config set backup_limit 10 exits 0"

# 6. config get backup_limit
out=$(run_schedule config get backup_limit 2>&1)
rc=$?
assert_equals "10" "$(echo "$out" | tr -d '[:space:]')" "config get backup_limit returns 10"

unset XDG_CONFIG_HOME

rm -rf "$FAKE_XDG_CONFIG"
rm -rf "$FAKE_RELAUNCH_HOME"

print_summary

