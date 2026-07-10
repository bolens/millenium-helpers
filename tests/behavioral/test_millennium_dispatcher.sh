#!/usr/bin/env bash
# Behavioral tests for scripts/millennium.sh (unified dispatcher)
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

DISPATCHER="${REPO_ROOT}/scripts/millennium.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: millennium.sh ===${NC}"

out=$(bash "$DISPATCHER" help 2>&1)
rc=$?
assert_success "$rc" "millennium help exits 0"
assert_contains "$out" "Usage:" "millennium help prints usage"
assert_contains "$out" "diag" "millennium help documents diag"
assert_contains "$out" "doctor" "millennium help documents doctor alias"
assert_contains "$out" "upgrade" "millennium help documents upgrade"
assert_contains "$out" "schedule" "millennium help documents schedule"

out=$(bash "$DISPATCHER" --help 2>&1)
rc=$?
assert_success "$rc" "millennium --help exits 0"

out=$(bash "$DISPATCHER" 2>&1)
rc=$?
assert_success "$rc" "millennium with no args defaults to help and exits 0"
assert_contains "$out" "Usage:" "millennium with no args prints usage"

out=$(bash "$DISPATCHER" notacommand 2>&1)
rc=$?
assert_failure "$rc" "millennium unknown command exits non-zero"
assert_contains "$out" "Unknown command" "millennium unknown command explains itself"

out=$(bash "$DISPATCHER" upgrad 2>&1)
rc=$?
assert_failure "$rc" "millennium typo command exits non-zero"
assert_contains "$out" "Did you mean 'upgrade'" "millennium typo suggests closest command"

# doctor alias → millennium-diag doctor
mock_cmd "millennium-diag" 'echo "diag-ok $*"; exit 0'
out=$(PATH="${MOCK_BIN}:$PATH" bash "$DISPATCHER" doctor --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium doctor dispatches successfully"
assert_contains "$out" "diag-ok" "millennium doctor invokes millennium-diag"
assert_contains "$out" "doctor" "millennium doctor forwards doctor subcommand"
assert_contains "$out" "--dry-run" "millennium doctor forwards extra args"

# Dispatch to sibling scripts in the same checkout directory
# Prefer PATH mock over sibling .sh when both exist — dispatcher uses command -v first.
# Point PATH mock and also verify args are forwarded.
out=$(PATH="${MOCK_BIN}:$PATH" bash "$DISPATCHER" diag --json 2>&1)
rc=$?
assert_success "$rc" "millennium diag dispatches successfully"
assert_contains "$out" "diag-ok" "millennium diag invokes millennium-diag"
assert_contains "$out" "--json" "millennium diag forwards arguments"

mock_cmd "millennium-upgrade" 'echo "upgrade-ok $*"; exit 0'
out=$(PATH="${MOCK_BIN}:$PATH" bash "$DISPATCHER" upgrade --channel beta --yes 2>&1)
rc=$?
assert_success "$rc" "millennium upgrade dispatches successfully"
assert_contains "$out" "upgrade-ok" "millennium upgrade invokes millennium-upgrade"
assert_contains "$out" "--channel beta" "millennium upgrade forwards channel args"

print_summary
