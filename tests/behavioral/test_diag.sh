#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-diag.sh (thin-wrap → Go).
# Dual-OS smokes live in .github/workflows/go.yml.
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

print_summary
