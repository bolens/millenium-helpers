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

out=$(bash "$DIAG_SH" -h 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh -h exits 0"
assert_contains "$out" "Usage:" "millennium-diag.sh -h prints usage"

# --- Unknown option ---
out=$(bash "$DIAG_SH" --bogus 2>&1)
rc=$?
assert_failure "$rc" "millennium-diag.sh exits non-zero on an unknown option"
assert_contains "$out" "Unknown option" "millennium-diag.sh reports the unrecognized option"
assert_contains "$out" "Usage:" "millennium-diag.sh shows usage after an unrecognized option"

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
out=$(timeout 20 bash "$DIAG_SH" doctor --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh doctor --dry-run completes without error"
assert_contains "$out" "DRY RUN MODE" "millennium-diag.sh doctor --dry-run announces dry-run mode"
assert_contains "$out" "Doctor" "millennium-diag.sh doctor --dry-run runs the doctor routine"

# -f/--fix is an alias for doctor
out=$(timeout 20 bash "$DIAG_SH" -f --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-diag.sh -f --dry-run (doctor alias) completes without error"
assert_contains "$out" "Doctor" "millennium-diag.sh -f --dry-run runs the doctor routine via its -f alias"

print_summary
