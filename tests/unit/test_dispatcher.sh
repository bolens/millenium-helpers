#!/usr/bin/env bash
# Unit tests for scripts/lib/dispatcher.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../../scripts/lib/dispatcher.sh
source "${REPO_ROOT}/scripts/lib/dispatcher.sh"

echo -e "${YELLOW}=== Unit tests: dispatcher.sh ===${NC}"

# --- suggest_command ---
assert_equals "upgrade" "$(suggest_command upgrade)" "suggest_command exact match returns upgrade"
assert_equals "upgrade" "$(suggest_command upg)" "suggest_command prefers upgrade for upg"
assert_equals "diag" "$(suggest_command dia)" "suggest_command prefers diag for dia"
assert_equals "schedule" "$(suggest_command sched)" "suggest_command prefers schedule for sched"
assert_equals "" "$(suggest_command z)" "suggest_command returns empty for weak single-letter match"
assert_equals "doctor" "$(suggest_command doct)" "suggest_command prefers doctor for doct"
assert_equals "purge" "$(suggest_command purg)" "suggest_command prefers purge for purg"
assert_equals "theme" "$(suggest_command them)" "suggest_command prefers theme for them"

# --- exec_dispatcher_command (missing target) ---
# Empty PATH so a host-installed millennium-* cannot satisfy command -v.
fake_root=$(mktemp -d 2>/dev/null || mktemp -d -t disp.XXXXXX)
export DISPATCHER_SCRIPT_DIR="$fake_root"
rc=0
out=$(
  # shellcheck disable=SC2123 # empty PATH hides host millennium-* binaries
  PATH=
  export PATH
  unset -f command 2>/dev/null || true
  exec_dispatcher_command "diag" 2>&1
) || rc=$?
assert_contains "$out" "not found" "exec_dispatcher_command reports missing target"
assert_failure "$rc" "exec_dispatcher_command exits non-zero when missing"
rm -rf "$fake_root"
unset DISPATCHER_SCRIPT_DIR

print_summary
