#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-schedule.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

SCHEDULE_SH="${REPO_ROOT}/scripts/millennium-schedule.sh"
GO_BIN="${REPO_ROOT}/bin/millennium"

# Phase 6c: long-name config thin-wraps to Go — ensure a dispatcher exists.
if [[ ! -x "$GO_BIN" ]]; then
  make -C "$REPO_ROOT" build
fi
[[ -x "$GO_BIN" ]] || {
  echo "error: ${GO_BIN} required for schedule config tests" >&2
  exit 1
}

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
assert_contains "$out" "setup" "millennium-schedule --help documents the setup command"
assert_contains "$out" "config" "millennium-schedule --help documents the config command"

out=$(run_schedule --version 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule --version exits 0"
assert_contains "$out" "$EXPECTED_VERSION" "millennium-schedule --version prints VERSION file value"

out=$(run_schedule 2>&1)
rc=$?
assert_failure "$rc" "millennium-schedule with no command exits non-zero"
assert_contains "$out" "Usage:" "millennium-schedule with no command prints usage"

# --- Invalid channel argument ---

out=$(run_schedule enable bogus-channel --dry-run 2>&1)
rc=$?
assert_failure "$rc" "millennium-schedule enable rejects an unrecognized channel argument"
assert_contains "$out" "Unknown channel" "millennium-schedule enable reports the unrecognized channel"

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
if [[ "$(uname -s)" == "Linux" ]]; then
  assert_contains "$out" "system and user scopes" "millennium-schedule disable --dry-run mentions both systemd scopes"
  assert_contains "$out" "system units under" "millennium-schedule disable --dry-run announces system-scope cleanup"
  assert_contains "$out" "user units under" "millennium-schedule disable --dry-run announces user-scope cleanup"
fi

# --- status (no timer/service configured) ---

out=$(run_schedule status 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule status exits 0 when nothing is configured"
assert_contains "$out" "not installed/configured" "millennium-schedule status reports the timer as unconfigured"
assert_contains "$out" "millennium schedule enable" "millennium-schedule status when disabled prints the enable command"

# --- Unknown command typo suggestion ---
out=$(run_schedule stauts 2>&1)
rc=$?
assert_failure "$rc" "millennium-schedule unknown command exits non-zero"
assert_contains "$out" "Unknown command" "millennium-schedule reports unknown command for typos"
assert_contains "$out" "Did you mean 'status'" "millennium-schedule suggests status for stauts typo"

# --- status (timer configured) includes summary CTAs ---
mkdir -p "${FAKE_XDG_CONFIG}/systemd/user"
cat > "${FAKE_XDG_CONFIG}/systemd/user/millennium-update.timer" <<'EOF'
[Timer]
OnCalendar=daily
EOF
cat > "${FAKE_XDG_CONFIG}/systemd/user/millennium-update.service" <<'EOF'
[Service]
ExecStart=/usr/bin/sudo -n /usr/local/bin/millennium-upgrade --channel beta --quiet
EOF
mock_cmd "systemctl" 'echo "systemctl: $*"; exit 0'
out=$(run_schedule status 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule status exits 0 when timer files exist"
if [[ "$(uname)" != "Darwin" ]]; then
  assert_contains "$out" "Scheduler summary" "millennium-schedule status when enabled prints a summary section"
  assert_contains "$out" "millennium schedule disable" "millennium-schedule status when enabled prints disable CTA"
  assert_contains "$out" "Channel" "millennium-schedule status when enabled prints channel"
fi
rm -f "${FAKE_XDG_CONFIG}/systemd/user/millennium-update.timer" "${FAKE_XDG_CONFIG}/systemd/user/millennium-update.service"
rm -f "${MOCK_BIN}/systemctl"

# --- --quiet is accepted ---
out=$(run_schedule status --quiet 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule status --quiet exits 0"
assert_not_contains "$out" "Unknown option" "millennium-schedule accepts --quiet"

# --- pre-update: Steam not running ---

mock_cmd "pgrep" 'exit 1'
out=$(MILLENNIUM_SCHEDULER=1 run_schedule pre-update 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule pre-update exits 0 when Steam isn't running"
assert_contains "$out" "not running" "millennium-schedule pre-update reports that Steam is not running"
mock_cmd "pgrep" 'exit 1'

# --- pre-update: requires scheduler gate ---
out=$(run_schedule pre-update 2>&1)
rc=$?
assert_failure "$rc" "millennium-schedule pre-update refuses manual invocation"
assert_contains "$out" "only for the scheduler" "millennium-schedule pre-update explains scheduler-only gate"

# --- post-update: no saved relaunch state ---

rm -f "$EXPECTED_STATE_FILE"
out=$(MILLENNIUM_SCHEDULER=1 run_schedule post-update 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule post-update exits 0 with no saved relaunch state (diag mocked to pass)"
assert_contains "$out" "No saved relaunch state" "millennium-schedule post-update reports no relaunch state was found"

# --- post-update: diagnostics failure aborts relaunch ---

mock_cmd "millennium-diag" 'exit 1'
out=$(MILLENNIUM_SCHEDULER=1 run_schedule post-update 2>&1)
rc=$?
assert_failure "$rc" "millennium-schedule post-update exits non-zero when diagnostics fail"
assert_contains "$out" "failed verification" "millennium-schedule post-update explains the verification failure"
mock_cmd "millennium-diag" 'exit 0'

# --- post-update with saved state must not launch host Steam under TEST_SUITE_RUN ---
# Ownership checks require the state file owner to match RUNNING_USER (the
# invoking user). Point getent's home at the fake dir while keeping the
# username as the real user so _is_safe_relaunch_state_file accepts it.
real_user="$(id -un)"
mock_cmd "getent" 'echo "'"${real_user}"':x:1000:1000::'"${FAKE_RELAUNCH_HOME}"':/bin/bash"'
mkdir -p "$(dirname "$EXPECTED_STATE_FILE")"
cat > "$EXPECTED_STATE_FILE" << EOF
export DISPLAY=':1'
export STEAM_ARGS=""
export WAS_FLATPAK='false'
EOF
mock_cmd "steam" 'echo "REAL_STEAM_INVOKED" >> "'"${MOCK_BIN}"'/steam.calls"; exit 0'
rm -f "${MOCK_BIN}/steam.calls"
out=$(MILLENNIUM_SCHEDULER=1 run_schedule post-update 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule post-update exits 0 when relaunch state exists under TEST_SUITE_RUN"
assert_contains "$out" "[TEST] Bypassing real Steam relaunch" "millennium-schedule post-update bypasses Steam relaunch under TEST_SUITE_RUN"
assert_file_not_exists "${MOCK_BIN}/steam.calls" "millennium-schedule post-update does not invoke steam under TEST_SUITE_RUN"
assert_file_not_exists "$EXPECTED_STATE_FILE" "millennium-schedule post-update consumes the relaunch state file"
mock_cmd "steam" 'exit 0'

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
assert_contains "$out" "stable" "config set validation mentions stable"
assert_contains "$out" "main" "config set validation mentions main"

# 4b. config set update_channel main
out=$(run_schedule config set update_channel main 2>&1)
rc=$?
assert_success "$rc" "millennium-schedule config set update_channel main exits 0"
out=$(run_schedule config get update_channel 2>&1)
assert_equals "main" "$(echo "$out" | tr -d '[:space:]')" "config get update_channel returns main"
out=$(run_schedule config set update_channel beta 2>&1)
assert_success "$?" "restore update_channel to beta after main test"

# 5. config set backup_limit
out=$(run_schedule config set backup_limit 10 2>&1)
rc=$?
assert_success "$rc" "config set backup_limit 10 exits 0"

# 6. config get backup_limit
out=$(run_schedule config get backup_limit 2>&1)
rc=$?
assert_equals "10" "$(echo "$out" | tr -d '[:space:]')" "config get backup_limit returns 10"

# --- Setup Wizard dynamic defaults when configuration exists ---
TEST_CONFIG_DIR=$(mktemp -d)
export XDG_CONFIG_HOME="${TEST_CONFIG_DIR}"

mkdir -p "${TEST_CONFIG_DIR}/millennium-helpers"
cat > "${TEST_CONFIG_DIR}/millennium-helpers/config.json" << EOF
{
  "update_channel": "beta",
  "github_token": "token_existing_pat",
  "backup_limit": 7,
  "backup_max_age_days": 14
}
EOF

# Mock systemctl to simulate timer not being enabled yet
mock_cmd "systemctl" "exit 1"

# Run setup wizard in dry-run mode first to test output prompts
out=$(echo -e "\n\n\n" | FORCE_WIZARD=true bash "$SCHEDULE_SH" setup --dry-run 2>&1)
assert_contains "$out" "default: 2 (Beta)" "setup wizard default channel is Beta when beta is configured"
assert_contains "$out" "background update timer? [y/N]" "setup wizard default scheduler is n (y/N) when config exists but not enabled"
assert_contains "$out" "Press Enter to keep it" "setup wizard explains blank keeps existing PAT"
assert_contains "$out" "GitHub PAT [keep existing]" "setup wizard prompts to keep existing token"
assert_contains "$out" "Kept existing GitHub PAT" "setup wizard confirms existing PAT was kept"
assert_contains "$out" "github_token: [set]" "setup wizard dry-run redacts an existing GitHub token"
assert_contains "$out" "backup_limit" "setup wizard tip mentions backup_limit"
assert_contains "$out" "backup_max_age_days" "setup wizard tip mentions backup_max_age_days"

# Run setup wizard in live mode to write config using defaults
echo -e "\n\n\n" | FORCE_WIZARD=true bash "$SCHEDULE_SH" setup >/dev/null 2>&1

val_ch=$(python3 -c "import json; print(json.load(open('${TEST_CONFIG_DIR}/millennium-helpers/config.json')).get('update_channel'))")
val_token=$(python3 -c "import json; print(json.load(open('${TEST_CONFIG_DIR}/millennium-helpers/config.json')).get('github_token'))")
val_limit=$(python3 -c "import json; print(json.load(open('${TEST_CONFIG_DIR}/millennium-helpers/config.json')).get('backup_limit'))")
val_age=$(python3 -c "import json; print(json.load(open('${TEST_CONFIG_DIR}/millennium-helpers/config.json')).get('backup_max_age_days'))")
assert_equals "beta" "$val_ch" "setup wizard preserves update_channel via default prompt"
assert_equals "token_existing_pat" "$val_token" "setup wizard preserves github_token via default prompt"
assert_equals "7" "$val_limit" "setup wizard preserves backup_limit when rewriting config"
assert_equals "14" "$val_age" "setup wizard preserves backup_max_age_days when rewriting config"

rm -f "${MOCK_BIN}/systemctl"
rm -rf "${TEST_CONFIG_DIR}"
unset XDG_CONFIG_HOME

unset XDG_CONFIG_HOME

rm -rf "$FAKE_XDG_CONFIG"
rm -rf "$FAKE_RELAUNCH_HOME"

print_summary
