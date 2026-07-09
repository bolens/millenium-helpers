#!/usr/bin/env bash
# Behavioral tests for scripts/millennium-theme.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

THEME_SH="${REPO_ROOT}/scripts/millennium-theme.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: millennium-theme.sh ===${NC}"

# Fake HOME with a fake native Steam directory so STEAM_DIR resolution
# doesn't depend on (or pollute) the real machine's Steam install.
FAKE_HOME=$(mktemp -d)
mkdir -p "${FAKE_HOME}/.local/share/Steam/steamui/skins"
mock_cmd "getent" "
if [[ \"\$1\" == 'passwd' ]]; then
  echo 'themetestuser:x:1000:1000::${FAKE_HOME}:/bin/bash'
else
  /usr/bin/getent \"\$@\"
fi
"
export SUDO_USER="themetestuser"

run_theme() {
  bash "$THEME_SH" "$@"
}

# --- Help output ---

out=$(run_theme --help 2>&1)
rc=$?
assert_success "$rc" "millennium-theme --help exits 0"
assert_contains "$out" "list" "millennium-theme --help documents the list command"
assert_contains "$out" "install" "millennium-theme --help documents the install command"
assert_contains "$out" "update" "millennium-theme --help documents the update command"
assert_contains "$out" "remove" "millennium-theme --help documents the remove command"

# --- No command given ---

out=$(run_theme 2>&1)
rc=$?
assert_failure "$rc" "millennium-theme with no command exits non-zero"
assert_contains "$out" "Usage:" "millennium-theme with no command prints usage"

# --- list: empty skins directory ---

out=$(run_theme list 2>&1)
rc=$?
assert_success "$rc" "millennium-theme list exits 0 on an empty skins directory"
assert_contains "$out" "No themes installed" "millennium-theme list reports no themes when skins dir is empty"

out=$(run_theme list --json 2>&1)
assert_valid_json "$out" "millennium-theme list --json produces valid JSON"
assert_equals "[]" "$out" "millennium-theme list --json returns an empty array when no themes are installed"

# --- list: with a locally-installed (non-GitHub) theme ---

mkdir -p "${FAKE_HOME}/.local/share/Steam/steamui/skins/MyLocalTheme"
out=$(run_theme list 2>&1)
assert_contains "$out" "MyLocalTheme" "millennium-theme list shows a manually-installed local theme"
assert_contains "$out" "Local" "millennium-theme list labels a theme without metadata.json as local"

out=$(run_theme list --json 2>&1)
assert_valid_json "$out" "millennium-theme list --json still produces valid JSON with a local theme present"
assert_contains "$out" '"type":"local"' "millennium-theme list --json marks the local theme's type correctly"
rm -rf "${FAKE_HOME}/.local/share/Steam/steamui/skins/MyLocalTheme"

# --- list: with a GitHub-tracked theme (has metadata.json) ---

mkdir -p "${FAKE_HOME}/.local/share/Steam/steamui/skins/GithubTheme"
cat > "${FAKE_HOME}/.local/share/Steam/steamui/skins/GithubTheme/metadata.json" << 'EOF'
{"commit": "1234567890abcdef1234567890abcdef12345678", "owner": "someowner", "repo": "somerepo"}
EOF
out=$(run_theme list 2>&1)
assert_contains "$out" "GithubTheme" "millennium-theme list shows a GitHub-tracked theme by name"
assert_contains "$out" "someowner/somerepo" "millennium-theme list shows the owner/repo of a GitHub-tracked theme"

out=$(run_theme list --json 2>&1)
assert_valid_json "$out" "millennium-theme list --json produces valid JSON with a GitHub theme present"
assert_contains "$out" '"type":"github"' "millennium-theme list --json marks the GitHub theme's type correctly"
assert_contains "$out" '"owner":"someowner"' "millennium-theme list --json includes the owner field"

# --- install: invalid argument format ---

out=$(run_theme install "not-a-valid-repo-spec" 2>&1)
rc=$?
assert_failure "$rc" "millennium-theme install rejects an argument without owner/repo format"
assert_contains "$out" "owner/repo" "millennium-theme install explains the required owner/repo format"

# --- install: already-existing theme directory ---

mock_cmd "jq" 'read -r _; echo "abcdef0123456789abcdef0123456789abcdef01"'
mock_cmd "curl" 'echo "{}"'
out=$(run_theme install "someowner/GithubTheme" 2>&1)
rc=$?
assert_failure "$rc" "millennium-theme install refuses to overwrite an existing theme directory"
assert_contains "$out" "already exists" "millennium-theme install explains that the theme directory already exists"
rm -f "${MOCK_BIN}/curl" "${MOCK_BIN}/jq"

# --- install: dry-run against a new theme (mocked GitHub API) ---

mock_cmd "jq" 'read -r _; echo "abcdef0123456789abcdef0123456789abcdef01"'
mock_cmd "curl" 'echo "{}"'
out=$(run_theme install "someowner/NewTheme" --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-theme install --dry-run succeeds for a new theme with mocked GitHub API"
assert_contains "$out" "DRY RUN" "millennium-theme install --dry-run announces dry-run mode"
assert_contains "$out" "someowner/NewTheme" "millennium-theme install --dry-run mentions the owner/repo being installed"
assert_file_not_exists "${FAKE_HOME}/.local/share/Steam/steamui/skins/NewTheme" "millennium-theme install --dry-run does not actually create the theme directory"
rm -f "${MOCK_BIN}/curl" "${MOCK_BIN}/jq"

# --- install: GitHub API failure surfaces a clear error ---

mock_cmd "curl" 'exit 1'
out=$(run_theme install "someowner/Unreachable" --dry-run 2>&1)
rc=$?
assert_failure "$rc" "millennium-theme install fails cleanly when the GitHub API is unreachable"
assert_contains "$out" "Error" "millennium-theme install reports an error when it cannot resolve the latest commit"
rm -f "${MOCK_BIN}/curl" "${MOCK_BIN}/jq"

# --- install: path traversal in the repo component is rejected ---

mock_cmd "jq" 'read -r _; echo "abcdef0123456789abcdef0123456789abcdef01"'
mock_cmd "curl" 'echo "{}"'
out=$(run_theme install "someowner/../../../../tmp/evil-theme" --dry-run 2>&1)
rc=$?
assert_failure "$rc" "millennium-theme install rejects a repo component containing path traversal"
assert_contains "$out" "Invalid" "millennium-theme install explains the repo component is invalid"
assert_file_not_exists "/tmp/evil-theme" "millennium-theme install does not create a directory outside SKINS_DIR"
rm -f "${MOCK_BIN}/curl" "${MOCK_BIN}/jq"

# --- remove: nonexistent theme ---

out=$(run_theme remove "NoSuchTheme" 2>&1)
rc=$?
assert_failure "$rc" "millennium-theme remove fails for a theme that isn't installed"
assert_contains "$out" "is not installed" "millennium-theme remove explains the theme isn't installed"

# --- remove: existing theme (dry-run leaves it in place) ---

out=$(run_theme remove "GithubTheme" --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-theme remove --dry-run exits 0 for an existing theme"
assert_contains "$out" "DRY RUN" "millennium-theme remove --dry-run announces dry-run mode"
assert_file_exists "${FAKE_HOME}/.local/share/Steam/steamui/skins/GithubTheme" "millennium-theme remove --dry-run does not actually delete the theme directory"

# --- remove: path traversal in the theme name is rejected ---

CANARY_FILE="$(mktemp 2>/dev/null || mktemp -t 'tmp')"
echo "do not delete me" > "$CANARY_FILE"
out=$(run_theme remove "../../../../..${CANARY_FILE}" 2>&1)
rc=$?
assert_failure "$rc" "millennium-theme remove rejects a theme name containing path traversal"
assert_contains "$out" "Invalid" "millennium-theme remove explains the theme name is invalid"
assert_file_exists "$CANARY_FILE" "millennium-theme remove does not delete a file outside SKINS_DIR"
rm -f "$CANARY_FILE"

# --- update: nonexistent theme ---

out=$(run_theme update "NoSuchTheme" 2>&1)
rc=$?
assert_failure "$rc" "millennium-theme update fails for a theme that isn't installed"
assert_contains "$out" "is not installed" "millennium-theme update explains the theme isn't installed"

# --- update: theme with no metadata.json is skipped gracefully ---

mkdir -p "${FAKE_HOME}/.local/share/Steam/steamui/skins/NoMetaTheme"
out=$(run_theme update "NoMetaTheme" 2>&1)
rc=$?
assert_success "$rc" "millennium-theme update exits 0 for a theme lacking metadata.json (skipped, not an error)"
assert_contains "$out" "does not have GitHub metadata" "millennium-theme update explains why it skipped the theme"

# --- update: already up-to-date theme (mocked GitHub API returns the same commit) ---

mock_cmd "curl" 'cat << '"'"'JSONEOF'"'"'
[{"sha": "1234567890abcdef1234567890abcdef12345678"}]
JSONEOF'
out=$(run_theme update "GithubTheme" 2>&1)
rc=$?
assert_success "$rc" "millennium-theme update exits 0 when the theme is already up to date"
assert_contains "$out" "already up to date" "millennium-theme update reports the theme is already current"
rm -f "${MOCK_BIN}/curl"

# --- update (no argument): updates all installed themes ---

mock_cmd "curl" 'cat << '"'"'JSONEOF'"'"'
[{"sha": "1234567890abcdef1234567890abcdef12345678"}]
JSONEOF'
out=$(run_theme update 2>&1)
rc=$?
assert_success "$rc" "millennium-theme update (no arg) exits 0 across a mix of theme types"
assert_contains "$out" "Updating All Installed Themes" "millennium-theme update (no arg) announces the bulk operation"
assert_contains "$out" "already up to date" "millennium-theme update (no arg) reports the up-to-date GithubTheme"
assert_contains "$out" "does not have GitHub metadata" "millennium-theme update (no arg) reports the metadata-less NoMetaTheme"
rm -f "${MOCK_BIN}/curl"

# --- Regression: `update --all` and `update -a` must be reachable ---
# The argument parser used to only capture ARG when it didn't start with '-',
# so `update --all`/`update -a` always fell into the "Unknown option" branch
# and exited 1, even though the internal update logic explicitly checks for
# ARG being empty, "--all", or "-a". Only bare `update` worked. This regression
# test guards against that bug reappearing.
out=$(bash "$THEME_SH" update --all --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-theme update --all is recognized and exits 0"
assert_contains "$out" "Updating All Installed Themes" "millennium-theme update --all runs the bulk-update path"
assert_not_contains "$out" "Unknown option" "millennium-theme update --all is not treated as an unknown option"

out=$(bash "$THEME_SH" update -a --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-theme update -a is recognized and exits 0"
assert_contains "$out" "Updating All Installed Themes" "millennium-theme update -a runs the bulk-update path"
assert_not_contains "$out" "Unknown option" "millennium-theme update -a is not treated as an unknown option"

rm -rf "$FAKE_HOME"

print_summary
