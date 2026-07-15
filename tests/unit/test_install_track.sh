#!/usr/bin/env bash
# Unit tests for scripts/lib/install_track.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"

# shellcheck source=../../scripts/lib/install_track.sh
source "${REPO_ROOT}/scripts/lib/install_track.sh"

echo -e "${YELLOW}=== Unit tests: install_track.sh ===${NC}"

# Stub latest-tag resolver so release-track tests stay offline.
release_fetch_latest_tag() {
  printf 'v2.6.2'
}

# --- resolve_helpers_install_track ---

resolve_helpers_install_track release "" linux
assert_equals "release" "$HELPERS_TRACK" "resolve release track"
assert_equals "v2.6.2" "$HELPERS_TRACK_REF" "resolve release ref is latest tag"
assert_contains "$HELPERS_TRACK_URL" "releases/download/v2.6.2/millennium-helpers-v2.6.2-linux-" "resolve release URL"
assert_equals "1" "$HELPERS_TRACK_NEEDS_SHA" "release track needs SHA"

resolve_helpers_install_track main "" linux
assert_equals "main" "$HELPERS_TRACK" "resolve main track"
assert_equals "main" "$HELPERS_TRACK_REF" "resolve main ref"
assert_contains "$HELPERS_TRACK_URL" "archive/refs/heads/main.tar.gz" "resolve main URL"
assert_equals "0" "$HELPERS_TRACK_NEEDS_SHA" "main track skips SHA"
assert_equals "1" "$HELPERS_TRACK_IS_SOURCE_ARCHIVE" "main is source archive"

resolve_helpers_install_track tag "v2.5.0" linux
assert_equals "tag" "$HELPERS_TRACK" "resolve tag track"
assert_equals "v2.5.0" "$HELPERS_TRACK_REF" "resolve tag ref"
assert_equals "2.5.0" "$HELPERS_TRACK_VERSION" "resolve tag version"
assert_contains "$HELPERS_TRACK_URL" "releases/download/v2.5.0/millennium-helpers-v2.5.0-linux-" "resolve tag URL"

resolve_helpers_install_track tag "2.5.0" windows
assert_equals "v2.5.0" "$HELPERS_TRACK_REF" "tag without v is normalized"
assert_contains "$HELPERS_TRACK_URL" "millennium-helpers-v2.5.0-windows-amd64.zip" "windows asset for tag"

out=$(resolve_helpers_install_track bogus "" linux 2>&1) && rc=0 || rc=$?
assert_failure "$rc" "unknown track fails"
assert_contains "$out" "invalid helpers track" "unknown track error mentions invalid helpers track"

# Env override URL
MILLENNIUM_HELPERS_RELEASE_URL="https://example.test/custom.tar.gz" \
  resolve_helpers_install_track release "" linux
assert_equals "https://example.test/custom.tar.gz" "$HELPERS_TRACK_URL" "MILLENNIUM_HELPERS_RELEASE_URL overrides"
unset MILLENNIUM_HELPERS_RELEASE_URL

# --- write / read / migrate meta ---

META_DIR=$(mktemp -d)
trap 'rm -rf "$META_DIR"' EXIT

write_helpers_install_meta "$META_DIR" "release" "v2.5.0" "2.5.0" "https://example.test/a.tar.gz" ""
assert_file_exists "${META_DIR}/install-meta.json" "write_helpers_install_meta creates install-meta.json"

read_helpers_install_meta "$META_DIR"
assert_equals "release" "$HELPERS_META_TRACK" "read meta track"
assert_equals "v2.5.0" "$HELPERS_META_REF" "read meta ref"
assert_equals "2.5.0" "$HELPERS_META_VERSION" "read meta version"

# Idempotent migrate when meta exists
migrate_helpers_install_meta_if_needed "$META_DIR" "manual" ""
read_helpers_install_meta "$META_DIR"
assert_equals "release" "$HELPERS_META_TRACK" "migrate skips when meta exists"

# Legacy migrate: manual → release
LEGACY=$(mktemp -d)
echo "1.2.3" > "${LEGACY}/VERSION"
migrate_helpers_install_meta_if_needed "$LEGACY" "manual" ""
read_helpers_install_meta "$LEGACY"
assert_equals "release" "$HELPERS_META_TRACK" "legacy manual migrates to release"
assert_equals "v1.2.3" "$HELPERS_META_REF" "legacy manual ref from VERSION"
migrated=$(python3 -c "import json; print(json.load(open('${LEGACY}/install-meta.json')).get('migrated_from'))")
assert_equals "legacy" "$migrated" "legacy migrate sets migrated_from"

# Legacy migrate: pacman-git → main
GIT_LEGACY=$(mktemp -d)
echo "0.0.0" > "${GIT_LEGACY}/VERSION"
migrate_helpers_install_meta_if_needed "$GIT_LEGACY" "pacman-git" ""
read_helpers_install_meta "$GIT_LEGACY"
assert_equals "main" "$HELPERS_META_TRACK" "pacman-git migrates to main"
assert_equals "main" "$HELPERS_META_REF" "pacman-git ref is main"

# Legacy migrate: checkout
CHECKOUT=$(mktemp -d)
mkdir -p "${CHECKOUT}/.git"
echo "9.9.9" > "${CHECKOUT}/VERSION"
# Without a real git repo, ref falls back to checkout
migrate_helpers_install_meta_if_needed "$CHECKOUT" "checkout" "$CHECKOUT"
read_helpers_install_meta "$CHECKOUT"
assert_equals "checkout" "$HELPERS_META_TRACK" "checkout method migrates to checkout"

rm -rf "$LEGACY" "$GIT_LEGACY" "$CHECKOUT"

# --- winget-git manifests exist and point at main ---
winget_git=$(cat "${REPO_ROOT}/packaging/winget-git/bolens.millenniumhelpers.git.installer.yaml")
assert_contains "$winget_git" "archive/refs/heads/main.zip" "winget-git installer uses main.zip"
assert_contains "$winget_git" "bolens.millenniumhelpers.git" "winget-git PackageIdentifier"

print_summary
