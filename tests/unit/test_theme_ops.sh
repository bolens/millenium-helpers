#!/usr/bin/env bash
# Unit tests for scripts/lib/theme_ops.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../../scripts/lib/logging.sh
source "${REPO_ROOT}/scripts/lib/logging.sh"
# shellcheck source=../../scripts/lib/theme_ops.sh
source "${REPO_ROOT}/scripts/lib/theme_ops.sh"

echo -e "${YELLOW}=== Unit tests: theme_ops.sh ===${NC}"

# --- _sanitize_theme_component ---
out=$(_sanitize_theme_component "GoodTheme" "theme name" 2>&1)
rc=$?
assert_success "$rc" "_sanitize_theme_component accepts a simple name"
assert_equals "" "$out" "_sanitize_theme_component is silent on success"

rc=0
out=$(_sanitize_theme_component ".." "theme name" 2>&1) || rc=$?
assert_contains "$out" "Invalid theme name" "_sanitize_theme_component rejects .."
assert_equals "1" "$rc" "_sanitize_theme_component exits 1 for .."

rc=0
out=$(_sanitize_theme_component "a/b" "theme name" 2>&1) || rc=$?
assert_contains "$out" "Invalid theme name" "_sanitize_theme_component rejects slash"
assert_equals "1" "$rc" "_sanitize_theme_component exits 1 for slash"

rc=0
out=$(_sanitize_theme_component "" "theme owner" 2>&1) || rc=$?
assert_contains "$out" "Invalid theme owner" "_sanitize_theme_component rejects empty"
assert_equals "1" "$rc" "_sanitize_theme_component exits 1 for empty"

# --- _resolve_theme_dir ---
SKINS_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t themeops.XXXXXX)
mkdir -p "${SKINS_DIR}/SafeTheme"
resolved=$(_resolve_theme_dir "SafeTheme" 2>&1)
rc=$?
assert_success "$rc" "_resolve_theme_dir accepts in-tree theme"
assert_contains "$resolved" "SafeTheme" "_resolve_theme_dir returns theme path"

rm -rf "$SKINS_DIR"

print_summary
