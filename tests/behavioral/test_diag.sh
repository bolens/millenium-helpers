#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-diag.sh
#
# millennium-diag.sh is the largest/most complex script (885 lines) covering
# many live system checks (binaries, hooks, flatpak, sudoers, systemd timer,
# permissions, completions) plus a "doctor" auto-repair mode. Rather than
# attempting to mock the entire system surface, this suite targets the
# narrower, high-value behavioral contracts: help/usage, argument validation,
# the `logs` subcommand's happy and error paths, and `--json` output
# structure/validity. Full doctor-repair-path testing is intentionally out of
# scope here given the size/risk tradeoff of mocking dozens of system checks.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
DIAG_SH="${REPO_ROOT}/scripts/millennium-diag.sh"

run_with_timeout() {
  if command -v timeout &>/dev/null; then
    timeout "$@"
  else
    shift
    "$@"
  fi
}

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: millennium-diag.sh ===${NC}"

# --- Help output ---
out=$(bash "$DIAG_SH" --help 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh --help exits 0"
assert_contains "$out" "Usage:" "millennium-diag.sh --help prints usage"
assert_contains "$out" "doctor" "millennium-diag.sh --help documents the doctor command"
assert_contains "$out" "--json" "millennium-diag.sh --help documents the --json option"
assert_contains "$out" "--yes" "millennium-diag.sh --help documents the --yes option"

out=$(bash "$DIAG_SH" -h 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh -h exits 0"
assert_contains "$out" "Usage:" "millennium-diag.sh -h prints usage"

# --- Version ---
out=$(bash "$DIAG_SH" --version 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh --version exits 0"
assert_contains "$out" "millennium-diag" "millennium-diag.sh --version prints command name"
assert_contains "$out" "2.2.0" "millennium-diag.sh --version prints VERSION file value"

# --- Unknown option ---
out=$(bash "$DIAG_SH" --bogus 2>&1)
rc=$?
assert_failure "$rc" "millennium-diag.sh exits non-zero on an unknown option"
assert_contains "$out" "Unknown option" "millennium-diag.sh reports the unrecognized option"
assert_contains "$out" "Try '" "millennium-diag.sh unknown option points at --help"
assert_not_contains "$out" "Run read-only diagnostics" "millennium-diag.sh unknown option does not dump full help"

# --- logs command: no logs found anywhere ---
FAKE_HOME=$(mktemp -d)
mock_cmd "getent" "
if [[ \"\$1\" == 'passwd' && \$# -eq 2 ]]; then
  echo \"\$2:x:1000:1000::${FAKE_HOME}:/bin/bash\"
else
  /usr/bin/getent \"\$@\"
fi
"
out=$(SUDO_USER='' USER=faketestuser bash "$DIAG_SH" logs 2>&1)
rc=$?
assert_failure "$rc" "millennium-diag.sh logs fails when no Steam log files exist for the user"
assert_contains "$out" "No Steam logs found" "millennium-diag.sh logs explains no logs were found"
rm -rf "$FAKE_HOME"
rm -f "${MOCK_BIN}/getent"

# --- logs command: happy path with a fabricated log file ---
FAKE_HOME=$(mktemp -d)
mkdir -p "${FAKE_HOME}/.local/share/Steam/logs"
cat > "${FAKE_HOME}/.local/share/Steam/logs/console-linux.txt" << 'EOF'
[2024-01-01 00:00:00] Some unrelated line
[2024-01-01 00:00:01] Millennium bootstrap loaded successfully
[2024-01-01 00:00:02] plugin_loader: initialized 2 plugins
EOF
mock_cmd "getent" "
if [[ \"\$1\" == 'passwd' && \$# -eq 2 ]]; then
  echo \"\$2:x:1000:1000::${FAKE_HOME}:/bin/bash\"
else
  /usr/bin/getent \"\$@\"
fi
"
out=$(SUDO_USER='' USER=faketestuser bash "$DIAG_SH" logs 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh logs succeeds when a matching Steam log file exists"
assert_contains "$out" "console-linux.txt" "millennium-diag.sh logs reports which log file it read"
assert_contains "$out" "Millennium bootstrap loaded successfully" "millennium-diag.sh logs surfaces Millennium-related log lines"
assert_not_contains "$out" "Some unrelated line" "millennium-diag.sh logs filters out unrelated log lines"
rm -rf "$FAKE_HOME"
rm -f "${MOCK_BIN}/getent"

# --- --json: valid JSON with expected keys ---
out=$(bash "$DIAG_SH" --json 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh --json exits 0"
assert_valid_json "$out" "millennium-diag.sh --json produces valid JSON"
assert_contains "$out" '"steam_running"' "millennium-diag.sh --json includes a steam_running key"
assert_contains "$out" '"update_channel"' "millennium-diag.sh --json includes an update_channel key"
assert_contains "$out" '"binaries_ok"' "millennium-diag.sh --json includes a binaries_ok key"

# --json output must contain ONLY the JSON object on stdout (report noise is
# redirected away), so it can be piped straight into a JSON parser.
first_char="${out:0:1}"
assert_equals "{" "$first_char" "millennium-diag.sh --json emits pure JSON on stdout with no leading report text"

# --- doctor --dry-run does not error out and clearly marks itself as a dry run ---
out=$(run_with_timeout 20 bash "$DIAG_SH" doctor --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh doctor --dry-run completes without error"
assert_contains "$out" "DRY RUN MODE" "millennium-diag.sh doctor --dry-run announces dry-run mode"
assert_contains "$out" "Doctor" "millennium-diag.sh doctor --dry-run runs the doctor routine"

# -f/--fix is an alias for doctor
out=$(run_with_timeout 20 bash "$DIAG_SH" -f --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh -f --dry-run (doctor alias) completes without error"
assert_contains "$out" "Doctor" "millennium-diag.sh -f --dry-run runs the doctor routine via its -f alias"

# --- --share: Share report option ---
CAPTURE_TEMP=$(mktemp 2>/dev/null || mktemp -t tmp.XXXXXX)
export MOCK_PAYLOAD_CAPTURE="${CAPTURE_TEMP}"
export GITHUB_TOKEN="github_pat_testtoken1234567890abcdef"

FAKE_HOME=$(mktemp -d)
mkdir -p "${FAKE_HOME}/.local/share/Steam/logs"
echo "Some millennium log line with ghp_MySecretToken12345678901234567890" > "${FAKE_HOME}/.local/share/Steam/logs/console-linux.txt"

mock_cmd "getent" "
if [[ \"\$1\" == 'passwd' && \$# -eq 2 ]]; then
  echo \"\$2:x:1000:1000::${FAKE_HOME}:/bin/bash\"
else
  /usr/bin/getent \"\$@\"
fi
"

# shellcheck disable=SC2016
mock_cmd "curl" '
payload_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data-binary" ]]; then
    payload_file="${2#@}"
    shift
  fi
  shift
done
if [[ -n "$payload_file" && -f "$payload_file" ]]; then
  cp "$payload_file" "${MOCK_PAYLOAD_CAPTURE}"
fi
echo "https://paste.rs/mocklink"
'

out=$(SUDO_USER='' USER=faketestuser bash "$DIAG_SH" logs --share 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh --share completes successfully"
assert_contains "$out" "Diagnostic report successfully shared" "millennium-diag.sh reports share success"
assert_contains "$out" "https://paste.rs/mocklink" "millennium-diag.sh prints the returned upload URL"

captured_content=$(cat "$CAPTURE_TEMP" 2>/dev/null || true)
assert_contains "$captured_content" "[REDACTED]" "Diagnostic report redacts tokens in upload"
assert_not_contains "$captured_content" "ghp_MySecretToken" "Diagnostic report does not leak raw tokens"
assert_not_contains "$captured_content" "github_pat_testtoken" "Diagnostic report does not leak env tokens"

# --share alone leaves clean_args empty; bash 3.2 + set -u must not abort.
out=$(SUDO_USER='' USER=faketestuser bash "$DIAG_SH" --share 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh --share alone completes successfully"
assert_contains "$out" "Diagnostic report successfully shared" "millennium-diag.sh --share alone reports share success"

# --share failure keeps a local sanitized report for retry/offline paste.
# shellcheck disable=SC2016
mock_cmd "curl" 'echo "upload failed"; exit 22'
STATE_DIR=$(mktemp -d)
out=$(SUDO_USER='' USER=faketestuser XDG_STATE_HOME="$STATE_DIR" bash "$DIAG_SH" --share 2>&1)
rc=$?
assert_failure "$rc" "millennium-diag.sh --share exits non-zero when upload fails"
assert_contains "$out" "Failed to upload" "millennium-diag.sh --share failure explains upload error"
assert_contains "$out" "Local sanitized report kept at" "millennium-diag.sh --share failure keeps a local report"
assert_contains "$out" "retry later" "millennium-diag.sh --share failure prints a retry tip"
kept=$(find "$STATE_DIR" -type f -name 'diag-share-failed-*.txt' 2>/dev/null | head -n1)
assert_file_exists "${kept:-/nonexistent}" "millennium-diag.sh --share failure writes a persistent report file"
rm -rf "$STATE_DIR"

# Clean up mock
rm -f "${MOCK_BIN}/curl"
rm -f "${MOCK_BIN}/getent"
rm -rf "$FAKE_HOME"
rm -f "$CAPTURE_TEMP"
unset MOCK_PAYLOAD_CAPTURE
unset GITHUB_TOKEN
# --- Channel detection from systemd service file ---
TEST_CONFIG_DIR=$(mktemp -d)
export XDG_CONFIG_HOME="${TEST_CONFIG_DIR}"

mkdir -p "${TEST_CONFIG_DIR}/systemd/user"
# Write service file with the new channel flag
cat > "${TEST_CONFIG_DIR}/systemd/user/millennium-update.service" << EOF
[Service]
ExecStart=/bin/bash -c 'sudo -n millennium-upgrade --channel beta'
EOF

out=$(bash "$DIAG_SH" --json 2>&1)
assert_contains "$out" '"update_channel": "beta"' "millennium-diag.sh --json correctly detects channel beta from systemd service file flags"

rm -rf "${TEST_CONFIG_DIR}"
unset XDG_CONFIG_HOME

# --- Obsolete legacy files detection and doctor cleanup ---
TEST_OBS_DIR=$(mktemp -d)
obs_file1="${TEST_OBS_DIR}/millennium-upgrade-stable"
obs_file2="${TEST_OBS_DIR}/millennium-upgrade-beta"
touch "$obs_file1" "$obs_file2"

# 1. Detection via JSON
out=$(DIAG_TEST_OBSOLETE_LIST="${obs_file1},${obs_file2}" DIAG_TEST_BYPASS_CHECKS=true bash "$DIAG_SH" --json 2>&1)
assert_contains "$out" '"clean_of_obsolete": false' "millennium-diag.sh --json detects presence of obsolete files"

# 2. Cleanup via doctor --dry-run
out=$(DIAG_TEST_OBSOLETE_LIST="${obs_file1},${obs_file2}" DIAG_TEST_BYPASS_CHECKS=true bash "$DIAG_SH" doctor --dry-run 2>&1)
assert_contains "$out" "rm -f ${obs_file1}" "millennium-diag.sh doctor --dry-run plans to remove first obsolete file"
assert_contains "$out" "rm -f ${obs_file2}" "millennium-diag.sh doctor --dry-run plans to remove second obsolete file"

# 3. Cleanup live doctor (stub schedule so a failed enable cannot abort later repairs)
mock_cmd "millennium-schedule" "exit 0"
out=$(DIAG_TEST_OBSOLETE_LIST="${obs_file1},${obs_file2}" DIAG_TEST_BYPASS_CHECKS=true bash "$DIAG_SH" doctor 2>&1)
assert_contains "$out" "Removing deprecated file: ${obs_file1}" "millennium-diag.sh doctor reports removing first obsolete file"
assert_contains "$out" "Removing deprecated file: ${obs_file2}" "millennium-diag.sh doctor reports removing second obsolete file"
assert_file_not_exists "$obs_file1" "First obsolete file was actually deleted"
assert_file_not_exists "$obs_file2" "Second obsolete file was actually deleted"
rm -f "${MOCK_BIN}/millennium-schedule"

# Empty obsolete list must not trip bash 3.2 unbound-array under set -u.
out=$(DIAG_TEST_OBSOLETE_LIST="" DIAG_TEST_BYPASS_CHECKS=true bash "$DIAG_SH" --json 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh --json with empty obsolete list exits 0"
assert_contains "$out" '"clean_of_obsolete": true' "millennium-diag.sh --json with empty obsolete list reports clean"

rm -rf "${TEST_OBS_DIR}"

# --- Default report next-steps footer (not JSON, not doctor) ---
out=$(DIAG_TEST_BYPASS_CHECKS=true DIAG_TEST_OBSOLETE_LIST="" bash "$DIAG_SH" 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh default report exits 0 with bypassed checks"
assert_contains "$out" "No issues detected" "millennium-diag.sh default report prints healthy next-steps footer"
assert_contains "$out" "millennium schedule status" "millennium-diag.sh healthy footer mentions schedule status"

# Force an obsolete-file issue so the footer suggests doctor
TEST_OBS_DIR2=$(mktemp -d)
obs_only="${TEST_OBS_DIR2}/millennium-upgrade-stable"
touch "$obs_only"
out=$(DIAG_TEST_BYPASS_CHECKS=true DIAG_TEST_OBSOLETE_LIST="$obs_only" bash "$DIAG_SH" 2>&1)
assert_contains "$out" "issue(s) detected" "millennium-diag.sh default report counts issues in next-steps footer"
assert_contains "$out" "millennium doctor" "millennium-diag.sh next-steps footer suggests doctor"
rm -rf "${TEST_OBS_DIR2}"

# JSON mode must not print the human next-steps footer
out=$(DIAG_TEST_BYPASS_CHECKS=true DIAG_TEST_OBSOLETE_LIST="" bash "$DIAG_SH" --json 2>&1)
assert_not_contains "$out" "issue(s) detected" "millennium-diag.sh --json does not print next-steps footer"
assert_not_contains "$out" "No issues detected. Your Millennium installation looks healthy" "millennium-diag.sh --json does not print healthy prose footer"

print_summary
