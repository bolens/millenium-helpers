#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-repair.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

REPAIR_SH="${REPO_ROOT}/scripts/millennium-repair.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: millennium-repair.sh ===${NC}"

# --- Help ---

out=$(bash "$REPAIR_SH" --help 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --help exits 0"
assert_contains "$out" "Usage:" "millennium-repair --help prints usage"
assert_contains "$out" "--skip-theme" "millennium-repair --help documents --skip-theme"

# --- Version ---

out=$(bash "$REPAIR_SH" --version 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --version exits 0"
assert_contains "$out" "millennium-repair" "millennium-repair --version prints command name"
assert_contains "$out" "2.2.0" "millennium-repair --version prints VERSION file value"

# --- Unknown option ---

out=$(bash "$REPAIR_SH" --bogus 2>&1)
rc=$?
assert_failure "$rc" "millennium-repair exits non-zero on an unknown option"
assert_contains "$out" "Unknown option" "millennium-repair reports the unrecognized option"
assert_contains "$out" "Usage:" "millennium-repair unknown option prints usage"

# --- Common test fixture: fake home with a native Steam dir ---

FAKE_HOME=$(mktemp -d)
mkdir -p "${FAKE_HOME}/.local/share/Steam/config/htmlcache"
mkdir -p "${FAKE_HOME}/.config/millennium"

mock_cmd "getent" "
if [[ \"\$1\" == 'passwd' ]]; then
  echo 'repairtestuser:x:1000:1000::${FAKE_HOME}:/bin/bash'
else
  /usr/bin/getent \"\$@\"
fi
"
export SUDO_USER="repairtestuser"
mock_cmd "pgrep" 'exit 1'  # Steam not running

run_repair() {
  bash "$REPAIR_SH" "$@"
}

# --- Dry-run repair with no active theme configured (defaults to "Steam") ---

out=$(run_repair --dry-run --skip-theme 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --dry-run --skip-theme exits 0"
assert_contains "$out" "DRY RUN MODE" "millennium-repair --dry-run announces dry-run mode"
assert_contains "$out" "Fixing ownership" "millennium-repair --dry-run reports the ownership-fixing step"
assert_contains "$out" "Clearing htmlcache" "millennium-repair --dry-run reports the htmlcache-clearing step"
assert_not_contains "$out" "Refreshing active theme" "millennium-repair --dry-run --skip-theme skips the theme refresh entirely"

# --- Dry-run repair without --skip-theme, with mocked GitHub API for the default Steam theme ---

mock_cmd "jq" 'read -r _; echo "9f5b9ea8fabc9cd3c4f46b638d78daa9c3da97dd"'
mock_cmd "curl" 'echo "{}"'
out=$(run_repair --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --dry-run (no skip-theme) exits 0 with mocked GitHub API"
assert_contains "$out" "Active Theme Detected: Steam" "millennium-repair --dry-run detects the default 'Steam' theme when no config exists"
assert_contains "$out" "Would refresh active theme" "millennium-repair --dry-run reports it would refresh the theme"
rm -f "${MOCK_BIN}/jq" "${MOCK_BIN}/curl"

# --- GitHub API failure (but connectivity check succeeds) falls back to the hardcoded default commit ---

# shellcheck disable=SC2016
mock_cmd "curl" '
for arg in "$@"; do
  if [[ "$arg" == "https://github.com" ]]; then
    exit 0
  fi
done
exit 1
'
out=$(run_repair --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --dry-run falls back gracefully when GitHub API is unreachable for the default theme"
assert_contains "$out" "Falling back to default" "millennium-repair --dry-run explains it fell back to the hardcoded default commit"
rm -f "${MOCK_BIN}/curl"

# --- Custom theme with metadata.json drives owner/repo detection ---

mkdir -p "${FAKE_HOME}/.local/share/Steam/millennium/themes/CustomTheme"
cat > "${FAKE_HOME}/.config/millennium/config.json" << 'EOF'
{"themes": {"activeTheme": "CustomTheme"}}
EOF
cat > "${FAKE_HOME}/.local/share/Steam/millennium/themes/CustomTheme/metadata.json" << 'EOF'
{"commit": "aaaa", "owner": "customowner", "repo": "customrepo"}
EOF

mock_cmd "jq" 'read -r _; echo "bbbb1111bbbb1111bbbb1111bbbb1111bbbb1111"'
mock_cmd "curl" 'echo "{}"'
out=$(run_repair --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --dry-run exits 0 for a custom theme with metadata"
assert_contains "$out" "Active Theme Detected: CustomTheme (customowner/customrepo)" "millennium-repair --dry-run detects the custom active theme and its GitHub owner/repo"
rm -f "${MOCK_BIN}/jq" "${MOCK_BIN}/curl"

# --- Custom theme WITHOUT metadata.json is skipped (no owner/repo to refresh from) ---

rm -f "${FAKE_HOME}/.local/share/Steam/millennium/themes/CustomTheme/metadata.json"
out=$(run_repair --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --dry-run exits 0 for a custom theme lacking metadata"
assert_contains "$out" "does not have GitHub metadata" "millennium-repair --dry-run explains it skips refreshing a theme without metadata"

# --- Dry-run must not touch disk when Steam is running ---
# capture_steam_env() creates a real state directory/file on disk; running
# it unconditionally (even under --dry-run, before the DRY_RUN gate that
# already protected close_steam_gracefully) contradicted --dry-run's
# documented "no changes will be made" guarantee.

mock_cmd "pgrep" 'echo 12345'  # Steam appears to be running
mock_cmd "runuser" 'echo "runuser called: $*" >> "'"${MOCK_BIN}"'/runuser.calls"'
relaunch_state_dir="${FAKE_HOME}/.local/state/millennium-helpers"
rm -rf "$relaunch_state_dir" "${MOCK_BIN}/runuser.calls"

out=$(run_repair --dry-run --skip-theme 2>&1)
rc=$?
assert_success "$rc" "millennium-repair --dry-run exits 0 when Steam is (mock) running"
assert_contains "$out" "Would capture Steam's environment and close it" "millennium-repair --dry-run announces it would capture/close Steam instead of doing so"
assert_file_not_exists "$relaunch_state_dir" "millennium-repair --dry-run does not create the relaunch state directory"
# As root, repair may call runuser only to resolve the target user's XDG dirs.
# Closing Steam must still be skipped under --dry-run.
if [[ -f "${MOCK_BIN}/runuser.calls" ]]; then
  runuser_calls=$(cat "${MOCK_BIN}/runuser.calls")
  assert_not_contains "$runuser_calls" "osascript" "millennium-repair --dry-run does not invoke runuser to quit Steam (osascript)"
  assert_not_contains "$runuser_calls" "flatpak" "millennium-repair --dry-run does not invoke runuser to stop Flatpak Steam"
  assert_contains "$runuser_calls" "XDG_" "millennium-repair --dry-run runuser calls (if any) are XDG lookups only"
else
  assert_file_not_exists "${MOCK_BIN}/runuser.calls" "millennium-repair --dry-run does not invoke runuser to close Steam"
fi

rm -f "${MOCK_BIN}/runuser.calls"
mock_cmd "pgrep" 'exit 1'  # restore: Steam not running, for any tests that might run after this one

rm -rf "$FAKE_HOME"

print_summary
