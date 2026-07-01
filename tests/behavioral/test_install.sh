#!/usr/bin/env bash
# Behavioral tests for install.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

INSTALL_SH="${REPO_ROOT}/install.sh"

echo -e "${YELLOW}=== Behavioral tests: install.sh ===${NC}"

# --- Help output ---

out=$(bash "$INSTALL_SH" --help 2>&1)
rc=$?
assert_success "$rc" "install.sh --help exits 0"
assert_contains "$out" "Usage:" "install.sh --help prints usage banner"
assert_contains "$out" "install" "install.sh --help documents the install command"
assert_contains "$out" "uninstall" "install.sh --help documents the uninstall command"

# --- Unknown option handling ---

out=$(bash "$INSTALL_SH" --bogus-flag 2>&1)
rc=$?
assert_failure "$rc" "install.sh exits non-zero on an unknown option"
assert_contains "$out" "Unknown argument" "install.sh reports the unrecognized option"

# --- Dry-run install (no root required, no filesystem side effects) ---

out=$(bash "$INSTALL_SH" install --dry-run 2>&1)
rc=$?
assert_success "$rc" "install.sh install --dry-run exits 0 without root"
assert_contains "$out" "DRY RUN MODE" "install.sh install --dry-run announces dry-run mode"
assert_contains "$out" "millennium-repair" "install.sh install --dry-run lists millennium-repair as a managed script"
assert_contains "$out" "millennium-mcp" "install.sh install --dry-run lists millennium-mcp as a managed script"
assert_not_contains "$out" "Traceback" "install.sh install --dry-run has no Python trailing tracebacks"

if [[ -f /usr/local/bin/millennium-repair ]]; then
  before_mtime=$(stat -c '%Y' /usr/local/bin/millennium-repair)
  bash "$INSTALL_SH" install --dry-run > /dev/null 2>&1
  after_mtime=$(stat -c '%Y' /usr/local/bin/millennium-repair)
  assert_equals "$before_mtime" "$after_mtime" "install.sh install --dry-run does not modify an already-installed script"
else
  assert_file_not_exists "/usr/local/bin/millennium-repair" "install.sh install --dry-run does not install millennium-repair when absent"
fi

# --- Dry-run uninstall ---

out=$(bash "$INSTALL_SH" uninstall --dry-run < /dev/null 2>&1)
rc=$?
assert_success "$rc" "install.sh uninstall --dry-run exits 0 without root"
assert_contains "$out" "DRY RUN MODE" "install.sh uninstall --dry-run announces dry-run mode"
assert_contains "$out" "Uninstalling" "install.sh uninstall --dry-run describes the uninstall action"

# --- check_root error message includes the real invocation args (regression test) ---

out=$(bash "$INSTALL_SH" install 2>&1 < /dev/null || true)
assert_contains "$out" "sudo" "install.sh without --dry-run and without root tells the user to use sudo"
assert_contains "$out" "install.sh install" "install.sh's sudo hint preserves the original arguments (e.g. 'install')"

print_summary
