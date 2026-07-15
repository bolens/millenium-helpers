#!/usr/bin/env bash
# Behavioral smoke for thin install.sh → millennium install.
# Fixture install/uninstall/sudoers coverage lives in go/internal/install (make test-go).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
INSTALL_SH="${REPO_ROOT}/install.sh"
GO_BIN="${REPO_ROOT}/bin/millennium"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"

if [[ ! -x "$GO_BIN" ]]; then
  make -C "$REPO_ROOT" build
fi

echo -e "${YELLOW}=== Behavioral tests: install.sh bootstrap smoke ===${NC}"

out=$(bash "$INSTALL_SH" --help 2>&1)
rc=$?
assert_success "$rc" "install.sh --help exits 0"
assert_contains "$out" "millennium install" "install.sh --help shows Go install usage"
assert_contains "$out" "--track" "install.sh --help documents --track"

out=$(bash "$INSTALL_SH" --version 2>&1)
rc=$?
assert_success "$rc" "install.sh --version exits 0"
assert_contains "$out" "$EXPECTED_VERSION" "install.sh --version prints VERSION"

out=$("$GO_BIN" install --help 2>&1)
rc=$?
assert_success "$rc" "millennium install --help exits 0"
assert_contains "$out" "--dry-run" "millennium install --help documents dry-run"

# Thin hand-off: bootstrap must reach Go dry-run without writing.
PREFIX=$(mktemp -d)
out=$(bash "$INSTALL_SH" install --dry-run --prefix "${PREFIX}/bin" --lib-dir "${PREFIX}/lib" --skip-wizard 2>&1)
rc=$?
assert_success "$rc" "install.sh install --dry-run exits 0"
assert_contains "$out" "DRY RUN MODE" "dry-run announces mode"
assert_file_not_exists "${PREFIX}/bin/millennium" "dry-run does not write binary"
rm -rf "$PREFIX"

echo -e "${YELLOW}--- test_install.sh summary: ${ASSERT_RUN:-?} run, ${ASSERT_FAIL:-?} failed ---${NC}"
[[ "${ASSERT_FAIL:-0}" -eq 0 ]]
