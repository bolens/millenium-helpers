#!/usr/bin/env bash
# Behavioral tests for thin install.sh → millennium install/uninstall.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
INSTALL_SH="${REPO_ROOT}/install.sh"
GO_BIN="${REPO_ROOT}/bin/millennium"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

if [[ ! -x "$GO_BIN" ]]; then
  make -C "$REPO_ROOT" build
fi

echo -e "${YELLOW}=== Behavioral tests: install bootstrap → Go ===${NC}"

# --- Help / version via bootstrap ---
out=$(bash "$INSTALL_SH" --help 2>&1)
rc=$?
assert_success "$rc" "install.sh --help exits 0"
assert_contains "$out" "millennium install" "install.sh --help shows Go install usage"
assert_contains "$out" "--track" "install.sh --help documents --track"

out=$(bash "$INSTALL_SH" --version 2>&1)
rc=$?
assert_success "$rc" "install.sh --version exits 0"
assert_contains "$out" "$EXPECTED_VERSION" "install.sh --version prints VERSION"

# --- millenium install --help ---
out=$("$GO_BIN" install --help 2>&1)
rc=$?
assert_success "$rc" "millennium install --help exits 0"
assert_contains "$out" "--dry-run" "millennium install --help documents dry-run"

# --- Dry-run install under fixture prefix ---
PREFIX=$(mktemp -d)
export MILLENNIUM_BASH_COMPLETION_DIR="${PREFIX}/bash"
export MILLENNIUM_ZSH_COMPLETION_DIR="${PREFIX}/zsh"
export MILLENNIUM_FISH_COMPLETION_DIR="${PREFIX}/fish"
export MILLENNIUM_NUSHELL_COMPLETION_DIR="${PREFIX}/nu"
export MILLENNIUM_MAN_DIR="${PREFIX}/man"

out=$(bash "$INSTALL_SH" install --dry-run --prefix "${PREFIX}/bin" --lib-dir "${PREFIX}/lib" --skip-wizard 2>&1)
rc=$?
assert_success "$rc" "install.sh install --dry-run exits 0"
assert_contains "$out" "DRY RUN MODE" "dry-run announces mode"
assert_contains "$out" "millennium-upgrade" "dry-run plans PATH twin"
assert_file_not_exists "${PREFIX}/bin/millennium" "dry-run does not write binary"

# --- Live install into fixture prefix ---
out=$(bash "$INSTALL_SH" install --prefix "${PREFIX}/bin" --lib-dir "${PREFIX}/lib" --skip-wizard 2>&1)
rc=$?
assert_success "$rc" "install.sh install into fixture prefix exits 0"
assert_file_exists "${PREFIX}/bin/millennium" "install writes millennium"
assert_file_exists "${PREFIX}/bin/millennium-upgrade" "install writes upgrade twin"
assert_file_exists "${PREFIX}/lib/common.sh" "install copies common.sh"
assert_file_exists "${PREFIX}/lib/install-meta.json" "install writes install-meta.json"
assert_file_exists "${PREFIX}/bash/millennium-helpers" "install copies bash completions"
assert_contains "$(cat "${PREFIX}/lib/install-meta.json")" '"track"' "install-meta includes track"

# --- Uninstall ---
out=$(bash "$INSTALL_SH" uninstall --prefix "${PREFIX}/bin" --lib-dir "${PREFIX}/lib" --dry-run 2>&1)
rc=$?
assert_success "$rc" "uninstall --dry-run exits 0"
assert_contains "$out" "DRY RUN MODE" "uninstall dry-run announces mode"

out=$(bash "$INSTALL_SH" uninstall --prefix "${PREFIX}/bin" --lib-dir "${PREFIX}/lib" 2>&1)
rc=$?
assert_success "$rc" "uninstall removes fixture install"
assert_file_not_exists "${PREFIX}/bin/millennium" "uninstall removes millennium"
assert_file_not_exists "${PREFIX}/lib/common.sh" "uninstall removes lib tree"

rm -rf "$PREFIX"

echo -e "${YELLOW}--- test_install.sh summary: ${ASSERT_RUN:-?} run, ${ASSERT_FAIL:-?} failed ---${NC}"
[[ "${ASSERT_FAIL:-0}" -eq 0 ]]
