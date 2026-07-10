#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-purge.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

PURGE_SH="${REPO_ROOT}/scripts/millennium-purge.sh"

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
assert_contains "$out" "Try '" "millennium-purge unknown option points at --help"
assert_not_contains "$out" "De-register and purge Millennium" "millennium-purge unknown option does not dump full help"

# --- Dry-run: no Steam running, no installed hooks ---

mock_cmd "pgrep" 'exit 1'
out=$(bash "$PURGE_SH" --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-purge --dry-run exits 0 without root"
assert_contains "$out" "DRY RUN MODE" "millennium-purge --dry-run announces dry-run mode"
assert_contains "$out" "Purging Millennium hooks" "millennium-purge --dry-run describes the purge action"
assert_contains "$out" "Dry run completed successfully" "millennium-purge --dry-run reports a successful simulated completion"

# --- Dry-run correctly identifies and would remove a millennium-owned hook symlink ---
# purge.sh only checks readlink's target STRING for the "/usr/lib/millennium"
# substring (it never dereferences the symlink), so the target doesn't need to
# actually exist on disk. We deliberately point at that literal path so the
# match is genuine and not coincidental with anything already installed on
# the test machine.

FAKE_HOME=$(mktemp -d)
mkdir -p "${FAKE_HOME}/.local/share/Steam/ubuntu12_32" "${FAKE_HOME}/.local/share/Steam/ubuntu12_64"
ln -sf "/usr/lib/millennium/libmillennium_bootstrap_x86.so" "${FAKE_HOME}/.local/share/Steam/ubuntu12_32/libXtst.so.6"

mock_cmd "getent" "
if [[ \"\$1\" == 'passwd' ]]; then
  echo 'purgetestuser:x:1999:1999::${FAKE_HOME}:/bin/bash'
  exit 0
fi
exit 1
"

out=$(bash "$PURGE_SH" --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-purge --dry-run exits 0 when a millennium-owned hook is present"
assert_contains "$out" "Removing 32-bit hook" "millennium-purge --dry-run identifies the millennium-owned 32-bit hook for removal"
# Use -L (symlink presence) rather than assert_file_exists (-e, which follows
# the link and would report a false negative here since the target is a
# deliberately non-existent path).
assert_symlink_exists "${FAKE_HOME}/.local/share/Steam/ubuntu12_32/libXtst.so.6" "millennium-purge --dry-run does not actually remove the symlink"

rm -rf "$FAKE_HOME"

# --- Game running aborts the purge ---

mock_cmd "pgrep" 'exit 0'  # pretend steam is running
mock_cmd "getent" "
if [[ \"\$*\" == *\"passwd\"* ]]; then
  echo 'purgetestuser:x:1999:1999::/tmp/nonexistent:/bin/bash'
  exit 0
fi
exit 1
"

# is_game_running from common.sh inspects /proc; in this sandboxed test run no
# process actually has SteamAppId set, so is_game_running will be false and
# the purge should proceed to attempt closing steam gracefully instead of
# aborting. We simply verify it doesn't crash and still completes the dry-run.
mock_cmd "runuser" 'exit 0'
mock_cmd "steam" 'exit 0'
out=$(bash "$PURGE_SH" --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-purge --dry-run handles a running Steam process without crashing"
assert_contains "$out" "Steam is currently running" "millennium-purge --dry-run detects the running Steam process"
assert_contains "$out" "Would confirm and close Steam" "millennium-purge --dry-run plans Steam close confirmation"

# --- Non-interactive purge without --yes must refuse ---
# Dry-run skips confirmation; a live non-TTY run without --yes must exit 1.
# Mock root so we reach the confirmation gate (not the sudo requirement).

mock_cmd "pgrep" 'exit 1'
mock_cmd "id" '
if [[ "$*" == "-u" ]]; then echo 0; exit 0; fi
if [[ "$*" == "-un" ]]; then echo root; exit 0; fi
/usr/bin/id "$@"
'
out=$(bash "$PURGE_SH" </dev/null 2>&1)
rc=$?
assert_failure "$rc" "millennium-purge without --yes refuses non-interactive purge"
assert_contains "$out" "Refusing to purge without confirmation" "millennium-purge explains non-interactive refusal"
assert_contains "$out" "--yes" "millennium-purge refusal mentions --yes"
rm -f "${MOCK_BIN}/id"

# --- --yes skips confirmation in non-interactive mode ---
# Stub rm and getent so a live --yes run cannot touch host Steam/Millennium files.

mock_cmd "id" '
if [[ "$*" == "-u" ]]; then echo 0; exit 0; fi
if [[ "$*" == "-un" ]]; then echo root; exit 0; fi
/usr/bin/id "$@"
'
mock_cmd "getent" 'exit 1'
mock_cmd "rm" 'exit 0'
out=$(bash "$PURGE_SH" --yes </dev/null 2>&1)
rc=$?
assert_success "$rc" "millennium-purge --yes completes without interactive confirmation"
assert_contains "$out" "Purging Millennium hooks" "millennium-purge --yes proceeds with purge"
assert_not_contains "$out" "Are you sure" "millennium-purge --yes does not prompt for confirmation"
assert_contains "$out" "successfully purged" "millennium-purge --yes reports success"
assert_contains "$out" "millennium schedule status" "millennium-purge --yes tips scheduler status after purge"
rm -f "${MOCK_BIN}/id" "${MOCK_BIN}/rm"

print_summary
