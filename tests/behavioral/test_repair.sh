#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-repair.sh (thin-wrap → Go, Phase 6ad)
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

REPAIR_SH="${REPO_ROOT}/scripts/millennium-repair.sh"
GO_BIN="${REPO_ROOT}/bin/millennium"

if [[ ! -x "$GO_BIN" ]]; then
  make -C "$REPO_ROOT" build
fi
[[ -x "$GO_BIN" ]] || {
  echo "error: ${GO_BIN} required for repair thin-wrap tests" >&2
  exit 1
}

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: millennium-repair.sh ===${NC}"

out=$(bash "$REPAIR_SH" --help 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --help exits 0"
assert_contains "$out" "Usage:" "millennium-repair --help prints usage"
assert_contains "$out" "--skip-theme" "millennium-repair --help documents --skip-theme"
assert_contains "$out" "--yes" "millennium-repair --help documents --yes"

out=$(bash "$REPAIR_SH" --version 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --version exits 0"
assert_contains "$out" "millennium-repair" "millennium-repair --version prints command name"
assert_contains "$out" "$EXPECTED_VERSION" "millennium-repair --version prints VERSION file value"

out=$(bash "$REPAIR_SH" --bogus 2>&1)
rc=$?
assert_failure "$rc" "millennium-repair exits non-zero on an unknown option"
assert_contains "$out" "Unknown option" "millennium-repair reports the unrecognized option"

FAKE_HOME=$(mktemp -d)
export HOME="$FAKE_HOME"
export MOCK_LIB_DIR="$FAKE_HOME/lib"
export STEAM="$FAKE_HOME/.local/share/Steam"
mkdir -p "$STEAM/ubuntu12_32" "$STEAM/ubuntu12_64" "$STEAM/config/htmlcache" \
  "$MOCK_LIB_DIR/millennium" "$FAKE_HOME/.local/share/millennium"
printf 'stub\n' >"$MOCK_LIB_DIR/millennium/libmillennium_bootstrap_x86.so"
printf 'stub\n' >"$MOCK_LIB_DIR/millennium/libmillennium_bootstrap_hhx64.so"
printf 'x\n' >"$STEAM/config/htmlcache/blob"

out=$(bash "$REPAIR_SH" --dry-run --skip-theme 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --dry-run exits 0"
assert_contains "$out" "DRY RUN" "millennium-repair --dry-run announces mode"
assert_contains "$out" "Would link hook" "millennium-repair --dry-run plans hooks"
assert_contains "$out" "Skipping theme" "millennium-repair --dry-run honors --skip-theme"
assert_file_exists "$STEAM/config/htmlcache/blob" "dry-run does not clear htmlcache"

out=$(bash "$REPAIR_SH" --yes --skip-theme 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --yes --skip-theme exits 0"
assert_contains "$out" "Fixed hook" "millennium-repair live restores hooks"
assert_symlink_exists "$STEAM/ubuntu12_32/libXtst.so.6" "millennium-repair creates 32-bit hook symlink"
assert_contains "$out" "Repair completed successfully" "millennium-repair reports success"

rm -rf "$FAKE_HOME"
unset HOME MOCK_LIB_DIR STEAM

print_summary
