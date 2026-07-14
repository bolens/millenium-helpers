#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-diag.sh (thin-wrap → Go, Phase 6z).
# Dual-OS graduation smokes live in .github/workflows/go.yml (Endgame C).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

DIAG_SH="${REPO_ROOT}/scripts/millennium-diag.sh"
GO_BIN="${REPO_ROOT}/bin/millennium"

if [[ ! -x "$GO_BIN" ]]; then
  make -C "$REPO_ROOT" build
fi
[[ -x "$GO_BIN" ]] || {
  echo "error: ${GO_BIN} required for diag thin-wrap tests" >&2
  exit 1
}

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: millennium-diag.sh ===${NC}"

out=$(bash "$DIAG_SH" --help 2>&1)
rc=$?
assert_success "$rc" "millennium-diag --help exits 0"
assert_contains "$out" "Usage:" "millennium-diag --help prints usage"
assert_contains "$out" "doctor" "millennium-diag --help documents doctor"

out=$(bash "$DIAG_SH" --version 2>&1)
rc=$?
assert_success "$rc" "millennium-diag --version exits 0"
assert_contains "$out" "$EXPECTED_VERSION" "millennium-diag --version prints VERSION file value"

FAKE_HOME=$(mktemp -d)
export HOME="$FAKE_HOME"

out=$(bash "$DIAG_SH" 2>&1)
rc=$?
assert_success "$rc" "millennium-diag report exits 0"
assert_contains "$out" "Millennium Diagnostics Report" "millennium-diag prints report header"

out=$(bash "$DIAG_SH" --json 2>&1)
rc=$?
assert_success "$rc" "millennium-diag --json exits 0"
assert_contains "$out" "steam_running" "millennium-diag --json includes steam_running"
assert_contains "$out" "helpers_track" "millennium-diag --json includes helpers_track"

out=$(bash "$DIAG_SH" doctor --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-diag doctor --dry-run exits 0"
assert_contains "$out" "DRY RUN" "millennium-diag doctor --dry-run announces mode"

out=$(bash "$DIAG_SH" logs 2>&1)
rc=$?
if [[ "$rc" -eq 0 ]]; then
  assert_success "$rc" "millennium-diag logs exits 0 when logs available"
else
  assert_failure "$rc" "millennium-diag logs fails closed without Steam logs"
  assert_contains "$out" "No Steam logs found" "millennium-diag logs explains missing logs"
fi

rm -rf "$FAKE_HOME"
unset HOME

print_summary
