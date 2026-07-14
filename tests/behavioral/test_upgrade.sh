#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-upgrade.sh (thin-wrap → Go, Phase 6v)
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

FAKE_HOME=$(mktemp -d)
export HOME="$FAKE_HOME"
export MOCK_LIB_DIR="$FAKE_HOME/lib"
mkdir -p "$MOCK_LIB_DIR"

archive="$FAKE_HOME/fake.tgz"
printf 'payload\n' >"$FAKE_HOME/payload"
tar -czf "$archive" -C "$FAKE_HOME" payload
sha="$(sha256sum "$archive" | awk '{print $1}')"

out=$(bash "$UPGRADE_SH" --file "$archive" --sha256 "$sha" --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-upgrade --file --sha256 --dry-run exits 0"
assert_contains "$out" "DRY RUN" "millennium-upgrade dry-run announces mode"
assert_contains "$out" "Verified SHA256" "millennium-upgrade dry-run verifies digest"
assert_contains "$out" "Would install local archive" "millennium-upgrade dry-run plans local install"

out=$(bash "$UPGRADE_SH" --file "$archive" --sha256 "$(printf 'a%.0s' {1..64})" --dry-run 2>&1)
rc=$?
assert_failure "$rc" "millennium-upgrade --file with wrong SHA fails"
assert_contains "$out" "SHA256" "millennium-upgrade mismatch mentions SHA256"

out=$(bash "$UPGRADE_SH" --file "$archive" --dry-run 2>&1)
rc=$?
assert_failure "$rc" "millennium-upgrade --file without checksum fails"
assert_contains "$out" "--sha256" "millennium-upgrade explains checksum requirement"

mkdir -p "$MOCK_LIB_DIR/millennium.bak_smoke"
out=$(bash "$UPGRADE_SH" --rollback list 2>&1)
rc=$?
assert_success "$rc" "millennium-upgrade --rollback list exits 0"
assert_contains "$out" "Available Backups" "millennium-upgrade lists backups"
assert_contains "$out" "smoke" "millennium-upgrade lists smoke backup"

rm -rf "$FAKE_HOME"
unset HOME MOCK_LIB_DIR

print_summary
