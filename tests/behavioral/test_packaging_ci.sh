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
WINDOWS_SHA_UC="$(printf '%s' "$WINDOWS_SHA" | tr '[:lower:]' '[:upper:]')"
assert_contains "$winget" "InstallerSha256: \"${WINDOWS_SHA_UC}\"" "Winget InstallerSha256 is quoted uppercase"
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

# --- release.yml Windows zip must ship the shared MCP Python server ---
windows_zip_block=$(awk '/Create Windows Release Zip/,/Calculate Checksums/' "${REPO_ROOT}/.github/workflows/release.yml")
assert_contains "$windows_zip_block" "scripts/millennium-mcp.py" "Windows release zip includes millennium-mcp.py"
assert_contains "$windows_zip_block" "completions/powershell/" "Windows release zip includes PowerShell completions"
assert_contains "$windows_zip_block" "scripts/windows/" "Windows release zip includes scripts/windows tree (diag lib modules)"
assert_contains "$windows_zip_block" "millennium-helpers-windows.zip" "release.yml builds trimmed Windows zip"

# Modular Windows diag lives under scripts/windows/lib — ensure the tree is shipped.
assert_file_exists "${REPO_ROOT}/scripts/windows/lib/Diag.ps1" "scripts/windows/lib/Diag.ps1 exists for release packaging"
assert_file_exists "${REPO_ROOT}/scripts/windows/lib/DiagInstall.ps1" "scripts/windows/lib/DiagInstall.ps1 exists for release packaging"
assert_file_exists "${REPO_ROOT}/scripts/windows/lib/DiagDoctor.ps1" "scripts/windows/lib/DiagDoctor.ps1 exists for release packaging"

# Release CD gate must wait on ShellCheck + completions, not only the test suite
release_gate=$(awk '/name: Wait for required CI/,/build-release:/' "${REPO_ROOT}/.github/workflows/release.yml")
assert_contains "$release_gate" "test-suite.yml" "release gate waits on test-suite.yml"
assert_contains "$release_gate" "shellcheck.yml" "release gate waits on shellcheck.yml"
assert_contains "$release_gate" "completions.yml" "release gate waits on completions.yml"

# --- Workflow path-filter sanity (avoid docs-only / LICENSE over-triggers) ---
scoop_ci=$(cat "${REPO_ROOT}/.github/workflows/package-install-windows.yml")
assert_contains "$scoop_ci" "millennium-mcp.py" "Scoop CI stages millennium-mcp.py beside scripts/windows"
assert_contains "$scoop_ci" "completions\\powershell" "Scoop CI stages PowerShell completions in the trimmed zip"
assert_not_contains "$scoop_ci" "- 'README.md'" "Scoop CI path filters do not trigger on README-only docs edits"
assert_not_contains "$scoop_ci" "- 'LICENSE'" "Scoop CI path filters do not trigger on LICENSE-only edits"

nix_wf=$(cat "${REPO_ROOT}/.github/workflows/nix.yml")
assert_contains "$nix_wf" "- 'VERSION'" "Nix CI path filters include VERSION"
assert_not_contains "$nix_wf" "- 'LICENSE'" "Nix CI path filters do not trigger on LICENSE-only edits"

pkg_wf=$(cat "${REPO_ROOT}/.github/workflows/pkgbuild.yml")
assert_contains "$pkg_wf" "- 'VERSION'" "PKGBUILD CI path filters include VERSION"
assert_not_contains "$pkg_wf" "- 'LICENSE'" "PKGBUILD CI path filters do not trigger on LICENSE-only edits"

suite_wf=$(cat "${REPO_ROOT}/.github/workflows/test-suite.yml")
assert_contains "$suite_wf" "- 'man/**'" "Test suite path filters include man pages"
assert_contains "$suite_wf" "- 'Formula/**'" "Test suite path filters include Formula"
assert_contains "$suite_wf" "- 'packaging/**'" "Test suite path filters include all packaging manifests"
assert_contains "$suite_wf" "- '.github/workflows/release.yml'" "Test suite path filters include release.yml"

ps_lint=$(cat "${REPO_ROOT}/.github/workflows/powershell-lint.yml")
assert_contains "$ps_lint" "completions/powershell" "PowerShell lint path filters include completions/powershell"

# Remaining packaging CIs: no docs/LICENSE over-triggers; VERSION where the package embeds it
for wf in homebrew.yml package-manifests.yml version-sync.yml man-pages.yml python-lint.yml; do
  body=$(cat "${REPO_ROOT}/.github/workflows/${wf}")
  assert_not_contains "$body" "- 'LICENSE'" "${wf} path filters do not trigger on LICENSE-only edits"
  assert_not_contains "$body" "- 'README.md'" "${wf} path filters do not trigger on README-only docs edits"
done

hb=$(cat "${REPO_ROOT}/.github/workflows/homebrew.yml")
assert_contains "$hb" "- 'Formula/**'" "Homebrew CI path filters include Formula"

vs=$(cat "${REPO_ROOT}/.github/workflows/version-sync.yml")
assert_contains "$vs" "- 'VERSION'" "version-sync path filters include VERSION"
assert_contains "$vs" "- 'Formula/**'" "version-sync path filters include Formula"

print_summary
