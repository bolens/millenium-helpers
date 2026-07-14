#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-upgrade.sh (thin-wrap → Go).
# Dual-OS smokes live in .github/workflows/go.yml.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

UPGRADE_SH="${REPO_ROOT}/scripts/millennium-upgrade.sh"
GO_BIN="${REPO_ROOT}/bin/millennium"

if [[ ! -x "$GO_BIN" ]]; then
  make -C "$REPO_ROOT" build
fi
[[ -x "$GO_BIN" ]] || {
  echo "error: ${GO_BIN} required for upgrade thin-wrap tests" >&2
  exit 1
}

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: millennium-upgrade.sh ===${NC}"

out=$(bash "$UPGRADE_SH" --help 2>&1)
rc=$?
assert_success "$rc" "millennium-upgrade --help exits 0"
assert_contains "$out" "Usage:" "millennium-upgrade --help prints usage"
assert_contains "$out" "--channel" "millennium-upgrade --help documents --channel"
assert_contains "$out" "--yes" "millennium-upgrade --help documents --yes"

out=$(bash "$UPGRADE_SH" --version 2>&1)
rc=$?
assert_success "$rc" "millennium-upgrade --version exits 0"
assert_contains "$out" "$EXPECTED_VERSION" "millennium-upgrade --version prints VERSION file value"

out=$(bash "$UPGRADE_SH" --bogus 2>&1)
rc=$?
assert_failure "$rc" "millennium-upgrade exits non-zero on an unknown option"
assert_contains "$out" "unknown option" "millennium-upgrade reports the unrecognized option"

print_summary
