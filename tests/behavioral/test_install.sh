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

setup_mock_bin
trap teardown_mock_bin EXIT

# Mock runuser to execute the command directly in our test environment
# shellcheck disable=SC2016
mock_cmd "runuser" '
shift  # drop -l
target_user="$1"; shift
shift  # drop -c
eval "$1"
'

echo -e "${YELLOW}=== Behavioral tests: install.sh ===${NC}"

# --- Help output ---

out=$(bash "$INSTALL_SH" --help 2>&1)
rc=$?
assert_success "$rc" "install.sh --help exits 0"
assert_contains "$out" "Usage:" "install.sh --help prints usage banner"
assert_contains "$out" "install" "install.sh --help documents the install command"
assert_contains "$out" "uninstall" "install.sh --help documents the uninstall command"

out=$(bash "$INSTALL_SH" --version 2>&1)
rc=$?
assert_success "$rc" "install.sh --version exits 0"
assert_contains "$out" "2.2.0" "install.sh --version prints VERSION file value"

# --- Man pages ship with the repo ---

for page in millennium-upgrade millennium-repair millennium-diag millennium-schedule \
            millennium-purge millennium-theme millennium-mcp; do
  assert_file_exists "${REPO_ROOT}/man/${page}.1" "man page exists for ${page}"
  man_body=$(cat "${REPO_ROOT}/man/${page}.1")
  assert_contains "$man_body" ".TH" "man/${page}.1 has a .TH title header"
  assert_contains "$man_body" ".SH NAME" "man/${page}.1 has a NAME section"
  assert_contains "$man_body" ".SH SYNOPSIS" "man/${page}.1 has a SYNOPSIS section"
done

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
assert_contains "$out" "Installing man pages" "install.sh install --dry-run installs man pages"
assert_contains "$out" "millennium-diag.1" "install.sh install --dry-run copies a man page file"
assert_not_contains "$out" "Traceback" "install.sh install --dry-run has no Python trailing tracebacks"

if [[ -f /usr/local/bin/millennium-repair ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    before_mtime=$(stat -f '%m' /usr/local/bin/millennium-repair)
    bash "$INSTALL_SH" install --dry-run > /dev/null 2>&1
    after_mtime=$(stat -f '%m' /usr/local/bin/millennium-repair)
  else
    before_mtime=$(stat -c '%Y' /usr/local/bin/millennium-repair)
    bash "$INSTALL_SH" install --dry-run > /dev/null 2>&1
    after_mtime=$(stat -c '%Y' /usr/local/bin/millennium-repair)
  fi
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
assert_contains "$out" "Uninstalling man pages" "install.sh uninstall --dry-run uninstalls man pages"

out=$(TARGET_DIR=/var/invalid/nonexistent bash "$INSTALL_SH" install 2>&1 < /dev/null || true)
# As root, check_root is skipped and install fails on the unwritable path instead.
# Force a non-root identity so we assert the sudo hint path CI expects.
mock_cmd "id" '
if [[ "$*" == "-u" ]]; then echo 1000; exit 0; fi
if [[ "$*" == "-un" ]]; then echo installtestuser; exit 0; fi
/usr/bin/id "$@"
'
out=$(TARGET_DIR=/var/invalid/nonexistent bash "$INSTALL_SH" install 2>&1 < /dev/null || true)
assert_contains "$out" "sudo" "install.sh without --dry-run and without root tells the user to use sudo"
assert_contains "$out" "install.sh install" "install.sh's sudo hint preserves the original arguments (e.g. 'install')"

# No args: bash 3.2 + set -u must not abort when echoing empty ORIGINAL_ARGS.
out=$(TARGET_DIR=/var/invalid/nonexistent bash "$INSTALL_SH" 2>&1 < /dev/null || true)
assert_contains "$out" "sudo" "install.sh with no args without root still tells the user to use sudo"
assert_contains "$out" "install.sh" "install.sh with no args still names itself in the sudo hint"
rm -f "${MOCK_BIN}/id"

# --- Interactive Wizard (Dry run) ---

# Run the installer with FORCE_WIZARD=true and input responses:
# Channel: 2 (beta)
# Enable schedule: y (yes)
# GitHub token: test_pat_token
out=$(echo -e "2\ny\ntest_pat_token" | FORCE_WIZARD=true bash "$INSTALL_SH" --dry-run 2>&1)
rc=$?
assert_success "$rc" "install.sh wizard --dry-run exits 0"
assert_contains "$out" "Configuration Wizard" "install.sh wizard announces itself"
assert_contains "$out" "Selected channel:" "install.sh wizard shows selected channel"
assert_contains "$out" "beta" "install.sh wizard captures beta channel"
assert_contains "$out" "Automated timer:" "install.sh wizard shows automated timer choice"
assert_contains "$out" "true" "install.sh wizard captures true scheduler choice"
assert_contains "$out" "Would write config" "install.sh wizard announces it would write config"
assert_contains "$out" "update_channel: beta" "install.sh wizard output contains correct channel"
assert_contains "$out" "github_token: test_pat_token" "install.sh wizard output contains correct token"
assert_contains "$out" "Configuring background update scheduler" "install.sh wizard triggers schedule enablement"

# --- Interactive Sudoers Validation Recovery ---

TEST_SUDO_DIR=$(mktemp -d)
export MOCK_SUDOERS_FILE="${TEST_SUDO_DIR}/millennium-helpers"

# Mock all file and system write operations that install.sh does in live mode
mock_cmd "mkdir" "exit 0"
mock_cmd "cp" "exit 0"
mock_cmd "chown" "exit 0"
mock_cmd "chmod" "exit 0"
mock_cmd "ln" "exit 0"
mock_cmd "restorecon" "exit 0"

# Mock visudo to fail initially
mock_cmd "visudo" "echo 'visudo: parse error in generated file' >&2; exit 1"

# Mock id command to trick installer into thinking we are root
mock_cmd "id" "echo 0"

out=$(echo -e "2" | FORCE_RECOVERY=true FORCE_WIZARD=false TARGET_DIR="${TEST_SUDO_DIR}" bash "$INSTALL_SH" install 2>&1)
rc=$?

assert_success "$rc" "install.sh with failing visudo and choosing option 2 (skip) exits successfully"
if [[ "$(uname)" != "Darwin" ]]; then
  assert_contains "$out" "visudo validation failed" "install.sh reports visudo failure"
  assert_contains "$out" "Skipping passwordless sudo setup" "install.sh announces skipping sudoers"
else
  assert_not_contains "$out" "visudo validation failed" "install.sh does not report visudo failure on macOS"
  assert_not_contains "$out" "Skipping passwordless sudo setup" "install.sh does not configure sudoers on macOS"
fi

# Reset mocks
rm -f "${MOCK_BIN}/id"
rm -f "${MOCK_BIN}/visudo"
rm -f "${MOCK_BIN}/mkdir"
rm -f "${MOCK_BIN}/cp"
rm -f "${MOCK_BIN}/chown"
rm -f "${MOCK_BIN}/chmod"
rm -f "${MOCK_BIN}/ln"
rm -f "${MOCK_BIN}/restorecon"
rm -rf "$TEST_SUDO_DIR"
unset MOCK_SUDOERS_FILE

# --- Obsolete legacy files cleanup test ---
TEST_TARGET_DIR=$(mktemp -d)

# Create dummy legacy files to prune
touch "${TEST_TARGET_DIR}/millennium-upgrade-stable"
touch "${TEST_TARGET_DIR}/millennium-upgrade-beta"

assert_file_exists "${TEST_TARGET_DIR}/millennium-upgrade-stable" "Legacy stable file exists before pruning"
assert_file_exists "${TEST_TARGET_DIR}/millennium-upgrade-beta" "Legacy beta file exists before pruning"

# Mock all file and system write operations
mock_cmd "mkdir" "exit 0"
mock_cmd "cp" "exit 0"
mock_cmd "chown" "exit 0"
mock_cmd "chmod" "exit 0"
mock_cmd "ln" "exit 0"
mock_cmd "restorecon" "exit 0"
mock_cmd "id" "echo 0"
mock_cmd "visudo" "exit 0"

# Run install with TARGET_DIR pointing to our temp directory
TARGET_DIR="${TEST_TARGET_DIR}" FORCE_RECOVERY=true FORCE_WIZARD=false bash "$INSTALL_SH" install >/dev/null 2>&1

# Verify obsolete files were pruned
assert_file_not_exists "${TEST_TARGET_DIR}/millennium-upgrade-stable" "install.sh install prunes legacy stable upgrade script"
assert_file_not_exists "${TEST_TARGET_DIR}/millennium-upgrade-beta" "install.sh install prunes legacy beta upgrade script"

# Clean up
rm -rf "$TEST_TARGET_DIR"
rm -f "${MOCK_BIN}/id" "${MOCK_BIN}/visudo" "${MOCK_BIN}/mkdir" "${MOCK_BIN}/cp" "${MOCK_BIN}/chown" "${MOCK_BIN}/chmod" "${MOCK_BIN}/ln" "${MOCK_BIN}/restorecon"

# --- Standalone piped installer test ---
STANDALONE_DIR=$(mktemp -d)

# Copy install.sh to the temp directory WITHOUT any other files
cp "$INSTALL_SH" "$STANDALONE_DIR/install.sh"

# Mock curl to avoid internet access and return a mock tarball of the local workspace
MOCK_TARBALL="${STANDALONE_DIR}/mock_repo.tar.gz"
MOCK_SRC_DIR="${STANDALONE_DIR}/millenium-helpers-main"
mkdir -p "$MOCK_SRC_DIR"
cp -r "$REPO_ROOT/install.sh" "$REPO_ROOT/scripts" "$REPO_ROOT/completions" "$REPO_ROOT/LICENSE" "$MOCK_SRC_DIR/"
tar -czf "$MOCK_TARBALL" -C "$STANDALONE_DIR" millenium-helpers-main

# Mock curl to return our local mock tarball
mock_cmd "curl" "cat '$MOCK_TARBALL'"

# Run install.sh in the standalone directory in dry-run mode
out=$(TARGET_DIR="$STANDALONE_DIR" bash "$STANDALONE_DIR/install.sh" install --dry-run 2>&1)
rc=$?

assert_success "$rc" "Standalone install.sh runs successfully"
assert_contains "$out" "Running in standalone/piped mode. Downloading repository..." "Standalone install.sh detects piped mode"
assert_contains "$out" "DRY RUN MODE" "Standalone install.sh successfully executes the downloaded script"

# Clean up
rm -rf "$STANDALONE_DIR"
rm -f "${MOCK_BIN}/curl"

print_summary

