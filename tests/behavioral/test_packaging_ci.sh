#!/usr/bin/env bash
# Behavioral tests for packaging CI helpers (hash hardening).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"

UPDATE="${REPO_ROOT}/scripts/ci/update-packaging-versions.sh"
WINGET_CHECK="${REPO_ROOT}/scripts/ci/check-winget-manifests.sh"

echo -e "${YELLOW}=== Behavioral tests: packaging CI helpers ===${NC}"

# --- Argument validation ---

out=$(bash "$UPDATE" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh without args exits non-zero"

out=$(bash "$UPDATE" "not-a-version" \
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh rejects invalid version"
assert_contains "$out" "invalid version" "update-packaging-versions.sh explains invalid version"

out=$(bash "$UPDATE" "9.9.9" "deadbeef" \
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh rejects short linux sha"
assert_contains "$out" "sha256" "update-packaging-versions.sh mentions sha256 on short hash"

ZERO="0000000000000000000000000000000000000000000000000000000000000000"
GOOD="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
out=$(bash "$UPDATE" "9.9.9" "$ZERO" "$GOOD" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh rejects all-zero linux sha"
assert_contains "$out" "placeholder" "update-packaging-versions.sh explains placeholder refusal"

out=$(bash "$UPDATE" "9.9.9" "$GOOD" "$ZERO" 2>&1); rc=$?
assert_failure "$rc" "update-packaging-versions.sh rejects all-zero windows sha"

# --- Successful update writes quoted Winget hash and verifies round-trip ---

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Minimal packaging tree mirroring the paths the updater touches.
mkdir -p "$WORK/Formula" "$WORK/packaging/scoop" "$WORK/packaging/winget" "$WORK/scripts/ci"
cp "$UPDATE" "$WORK/scripts/ci/"
cp "${REPO_ROOT}/Formula/millennium-helpers.rb" "$WORK/Formula/"
cp "${REPO_ROOT}/packaging/scoop/millennium-helpers.json" "$WORK/packaging/scoop/"
cp "${REPO_ROOT}/packaging/winget/"*.yaml "$WORK/packaging/winget/"
echo "0.0.0" > "$WORK/VERSION"

LINUX_SHA="1111111111111111111111111111111111111111111111111111111111111111"
WINDOWS_SHA="2222222222222222222222222222222222222222222222222222222222222222"

out=$(
  cd "$WORK" && bash scripts/ci/update-packaging-versions.sh \
    "3.4.5" "$LINUX_SHA" "$WINDOWS_SHA" 2>&1
)
rc=$?
assert_success "$rc" "update-packaging-versions.sh succeeds with valid hashes"
assert_contains "$out" "Verified packaging hashes" "update-packaging-versions.sh verifies written hashes"
assert_equals "3.4.5" "$(tr -d '[:space:]' < "$WORK/VERSION")" "VERSION file updated"

formula=$(cat "$WORK/Formula/millennium-helpers.rb")
assert_contains "$formula" "sha256 \"${LINUX_SHA}\"" "Formula receives lowercase linux sha256"
assert_contains "$formula" "releases/download/v3.4.5/millennium-helpers-linux.tar.gz" "Formula URL points at trimmed Linux release asset"
assert_contains "$formula" 'license "MIT"' "Formula declares MIT license"
assert_not_contains "$formula" 'version "3.4.5"' "Formula has no redundant version line after packaging update"

scoop=$(cat "$WORK/packaging/scoop/millennium-helpers.json")
assert_contains "$scoop" "\"hash\": \"${WINDOWS_SHA}\"" "Scoop receives windows sha256"
assert_contains "$scoop" "releases/download/v3.4.5/millennium-helpers-windows.zip" "Scoop URL points at trimmed Windows release asset"
assert_contains "$scoop" "millennium-helpers-windows.zip.sha256" "Scoop autoupdate hash uses .sha256 sidecar"

winget=$(cat "$WORK/packaging/winget/bolens.millenniumhelpers.installer.yaml")
assert_contains "$winget" "InstallerSha256: \"${WINDOWS_SHA^^}\"" "Winget InstallerSha256 is quoted uppercase"
assert_contains "$winget" "releases/download/v3.4.5/millennium-helpers-windows.zip" "Winget InstallerUrl points at trimmed Windows release asset"
assert_contains "$winget" "PackageVersion: 3.4.5" "Winget installer PackageVersion updated"
assert_contains "$winget" "InstallerType: zip" "Winget installer uses zip (no portable .ps1 claims)"
assert_not_contains "$winget" "NestedInstallerFiles" "Winget installer has no NestedInstallerFiles"
assert_not_contains "$winget" "PortableCommandAliases" "Winget installer has no PortableCommandAliases"

# --- check-winget-manifests accepts quoted placeholder on main ---

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  out=$(bash "$WINGET_CHECK" 2>&1)
  rc=$?
  assert_success "$rc" "check-winget-manifests.sh passes on current manifests"
  assert_contains "$out" "passed" "check-winget-manifests.sh reports success"
else
  echo -e "${YELLOW}SKIP:${NC} check-winget-manifests.sh (PyYAML not installed)"
fi

print_summary
