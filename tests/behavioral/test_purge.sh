#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-purge.sh (thin-wrap → Go)
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

PURGE_SH="${REPO_ROOT}/scripts/millennium-purge.sh"
GO_BIN="${REPO_ROOT}/bin/millennium"

if [[ ! -x "$GO_BIN" ]]; then
  make -C "$REPO_ROOT" build
fi
[[ -x "$GO_BIN" ]] || {
  echo "error: ${GO_BIN} required for purge thin-wrap tests" >&2
  exit 1
}

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: millennium-purge.sh ===${NC}"

# --- Help ---

out=$(bash "$PURGE_SH" --help 2>&1)
rc=$?
assert_success "$rc" "millennium-purge --help exits 0"
assert_contains "$out" "Usage:" "millennium-purge --help prints usage"
assert_contains "$out" "--yes" "millennium-purge --help documents the --yes option"

# --- Version ---

out=$(bash "$PURGE_SH" --version 2>&1)
rc=$?
assert_success "$rc" "millennium-purge --version exits 0"
assert_contains "$out" "millennium-purge" "millennium-purge --version prints command name"
assert_contains "$out" "$EXPECTED_VERSION" "millennium-purge --version prints VERSION file value"

# --- Unknown option ---

out=$(bash "$PURGE_SH" --bogus 2>&1)
rc=$?
assert_failure "$rc" "millennium-purge exits non-zero on an unknown option"
assert_contains "$out" "Unknown option" "millennium-purge reports the unrecognized option"

# --- Dry-run: baseline ---

FAKE_HOME=$(mktemp -d)
export HOME="$FAKE_HOME"
export MOCK_LIB_DIR="$FAKE_HOME/lib"
mkdir -p "$MOCK_LIB_DIR"

out=$(bash "$PURGE_SH" --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-purge --dry-run exits 0 without root"
assert_contains "$out" "DRY RUN MODE" "millennium-purge --dry-run announces dry-run mode"
assert_contains "$out" "Dry run completed successfully" "millennium-purge --dry-run reports a successful simulated completion"
assert_contains "$out" "millennium schedule disable" "millennium-purge --dry-run plans scheduler disable"

# --- Dry-run identifies millennium-owned hook ---

mkdir -p "${FAKE_HOME}/.local/share/Steam/ubuntu12_32" "${FAKE_HOME}/.local/share/Steam/ubuntu12_64"
ln -sf "/usr/lib/millennium/libmillennium_bootstrap_x86.so" "${FAKE_HOME}/.local/share/Steam/ubuntu12_32/libXtst.so.6"

out=$(bash "$PURGE_SH" --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-purge --dry-run exits 0 when a millennium-owned hook is present"
assert_contains "$out" "hook32" "millennium-purge --dry-run identifies the millennium-owned 32-bit hook for removal"
assert_symlink_exists "${FAKE_HOME}/.local/share/Steam/ubuntu12_32/libXtst.so.6" "millennium-purge --dry-run does not actually remove the symlink"

# --- Non-interactive purge without --yes must refuse ---

out=$(bash "$PURGE_SH" </dev/null 2>&1)
rc=$?
assert_failure "$rc" "millennium-purge without --yes refuses non-interactive purge"
assert_contains "$out" "Refusing to purge without confirmation" "millennium-purge explains non-interactive refusal"
assert_contains "$out" "--yes" "millennium-purge refusal mentions --yes"

# --- --yes skips confirmation ---

out=$(bash "$PURGE_SH" --yes </dev/null 2>&1)
rc=$?
assert_success "$rc" "millennium-purge --yes completes without interactive confirmation"
assert_contains "$out" "Purging Millennium hooks" "millennium-purge --yes proceeds with purge"
assert_not_contains "$out" "Are you sure" "millennium-purge --yes does not prompt for confirmation"
assert_contains "$out" "successfully purged" "millennium-purge --yes reports success"
assert_contains "$out" "millennium schedule status" "millennium-purge --yes tips scheduler status after purge"

rm -rf "$FAKE_HOME"
unset HOME MOCK_LIB_DIR

print_summary
