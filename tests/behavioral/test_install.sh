#!/usr/bin/env bash
# Behavioral tests for install.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
EXPECTED_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

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
assert_contains "$out" "$EXPECTED_VERSION" "install.sh --version prints VERSION file value"

# --- Man pages ship with the repo ---

for page in millennium millennium-upgrade millennium-repair millennium-diag millennium-schedule \
            millennium-purge millennium-theme millennium-mcp; do
  assert_file_exists "${REPO_ROOT}/man/${page}.1" "man page exists for ${page}"
  man_body=$(cat "${REPO_ROOT}/man/${page}.1")
  assert_contains "$man_body" ".TH" "man/${page}.1 has a .TH title header"
  assert_contains "$man_body" ".SH NAME" "man/${page}.1 has a NAME section"
  assert_contains "$man_body" ".SH SYNOPSIS" "man/${page}.1 has a SYNOPSIS section"
done
assert_contains "$(cat "${REPO_ROOT}/man/millennium-diag.1")" ".SH EXAMPLES" "man/millennium-diag.1 has an EXAMPLES section"
assert_contains "$(cat "${REPO_ROOT}/man/millennium-theme.1")" "SteamClientHomebrew" "man/millennium-theme.1 example mentions a real theme repo"

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
assert_contains "$out" "millennium" "install.sh install --dry-run lists the millennium dispatcher"
assert_contains "$out" "Installing man pages" "install.sh install --dry-run installs man pages"
assert_contains "$out" "millennium.1" "install.sh install --dry-run copies the dispatcher man page"
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
assert_contains "$out" "Disabling update scheduler" "install.sh uninstall --dry-run disables the update scheduler"
assert_contains "$out" "millennium" "install.sh uninstall --dry-run mentions the millennium dispatcher binary"

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
assert_contains "$out" "github_token: [set]" "install.sh wizard dry-run redacts the GitHub token"
assert_contains "$out" "Configuring background update scheduler" "install.sh wizard triggers schedule enablement"
assert_contains "$out" "backup_limit" "install.sh wizard tip mentions backup_limit"

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

# Build a trimmed-layout mock tarball (matches release.yml Linux payload)
MOCK_TARBALL="${STANDALONE_DIR}/mock_repo.tar.gz"
MOCK_PAYLOAD="${STANDALONE_DIR}/payload"
mkdir -p "$MOCK_PAYLOAD/scripts" "$MOCK_PAYLOAD/completions" "$MOCK_PAYLOAD/man"
cp "$REPO_ROOT/install.sh" "$REPO_ROOT/VERSION" "$REPO_ROOT/LICENSE" "$MOCK_PAYLOAD/"
cp "$REPO_ROOT/README.md" "$MOCK_PAYLOAD/" 2>/dev/null || true
cp "$REPO_ROOT/scripts/common.sh" \
  "$REPO_ROOT/scripts/millennium.sh" \
  "$REPO_ROOT/scripts/millennium-diag.sh" \
  "$REPO_ROOT/scripts/millennium-mcp.py" \
  "$REPO_ROOT/scripts/millennium-purge.sh" \
  "$REPO_ROOT/scripts/millennium-repair.sh" \
  "$REPO_ROOT/scripts/millennium-schedule.sh" \
  "$REPO_ROOT/scripts/millennium-theme.sh" \
  "$REPO_ROOT/scripts/millennium-upgrade.sh" \
  "$MOCK_PAYLOAD/scripts/"
cp -r "$REPO_ROOT/scripts/lib" "$MOCK_PAYLOAD/scripts/"
cp -r "$REPO_ROOT/completions/." "$MOCK_PAYLOAD/completions/" 2>/dev/null || true
cp -r "$REPO_ROOT/man/." "$MOCK_PAYLOAD/man/" 2>/dev/null || true
tar -czf "$MOCK_TARBALL" -C "$MOCK_PAYLOAD" .

# Mock curl: serve archive or matching .sha256 sidecar based on URL / -o path
# shellcheck disable=SC2016
mock_cmd "curl" '
out=""
url=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then out="$arg"; fi
  if [[ "$arg" == http* ]]; then url="$arg"; fi
  prev="$arg"
done
if [[ -z "$out" ]]; then
  echo "mock curl: missing -o" >&2
  exit 1
fi
if [[ "$url" == *.sha256 || "$out" == *.sha256 ]]; then
  archive="'"$MOCK_TARBALL"'"
  hash=$(sha256sum "$archive" | awk "{print \$1}")
  echo "${hash}  millennium-helpers-linux.tar.gz" > "$out"
  exit 0
fi
cat "'"$MOCK_TARBALL"'" > "$out"
'

# Run install.sh in the standalone directory in dry-run mode
out=$(TARGET_DIR="$STANDALONE_DIR" bash "$STANDALONE_DIR/install.sh" install --dry-run 2>&1)
rc=$?

assert_success "$rc" "Standalone install.sh runs successfully"
assert_contains "$out" "Running in standalone/piped mode. Downloading latest Linux release..." "Standalone install.sh detects piped mode"
assert_contains "$out" "SHA256 checksum verified." "Standalone install.sh verifies release checksum"
assert_contains "$out" "DRY RUN MODE" "Standalone install.sh successfully executes the downloaded script"

# Clean up
rm -rf "$STANDALONE_DIR"
rm -f "${MOCK_BIN}/curl"

# --- Isolated prefix install / uninstall (real filesystem) ---

PREFIX=$(mktemp -d)
PREFIX_BIN="${PREFIX}/bin"
PREFIX_LIB="${PREFIX}/lib/millennium-helpers"
PREFIX_BASH="${PREFIX}/share/bash-completion/completions"
PREFIX_ZSH="${PREFIX}/share/zsh/site-functions"
PREFIX_FISH="${PREFIX}/share/fish/vendor_completions.d"
PREFIX_NU="${PREFIX}/share/nushell/completions"
PREFIX_MAN="${PREFIX}/share/man/man1"
PREFIX_SUDOERS="${PREFIX}/sudoers.d/millennium-helpers"
mkdir -p "$PREFIX_BIN" "$PREFIX_BASH" "$PREFIX_ZSH" "$PREFIX_FISH" "$PREFIX_NU" "$PREFIX_MAN" "$(dirname "$PREFIX_SUDOERS")"

mock_cmd "id" '
if [[ "$*" == "-u" ]]; then echo 0; exit 0; fi
if [[ "$*" == "-un" ]]; then echo root; exit 0; fi
/usr/bin/id "$@"
'
mock_cmd "visudo" "exit 0"
mock_cmd "chown" "exit 0"
# Avoid touching the real user bus / crontab during isolated uninstall
mock_cmd "systemctl" "exit 0"
mock_cmd "crontab" "exit 0"

out=$(
  TARGET_DIR="$PREFIX_BIN" \
  MILLENNIUM_LIB_DIR="$PREFIX_LIB" \
  MILLENNIUM_BASH_COMPLETION_DIR="$PREFIX_BASH" \
  MILLENNIUM_ZSH_COMPLETION_DIR="$PREFIX_ZSH" \
  MILLENNIUM_FISH_COMPLETION_DIR="$PREFIX_FISH" \
  MILLENNIUM_NUSHELL_COMPLETION_DIR="$PREFIX_NU" \
  MILLENNIUM_MAN_DIR="$PREFIX_MAN" \
  MOCK_SUDOERS_FILE="$PREFIX_SUDOERS" \
  SUDO_USER="installtestuser" \
  FORCE_WIZARD=false \
  bash "$INSTALL_SH" install 2>&1
)
rc=$?
assert_success "$rc" "install.sh install into isolated prefix exits 0"

for cmd in millennium millennium-repair millennium-upgrade millennium-schedule \
           millennium-purge millennium-diag millennium-theme millennium-mcp; do
  assert_file_exists "${PREFIX_BIN}/${cmd}" "isolated install places ${cmd} in TARGET_DIR"
  assert_file_exists "${PREFIX_BASH}/${cmd}" "isolated install creates bash completion link for ${cmd}"
  assert_file_exists "${PREFIX_ZSH}/_${cmd}" "isolated install creates zsh completion link for ${cmd}"
  assert_file_exists "${PREFIX_FISH}/${cmd}.fish" "isolated install installs fish completion for ${cmd}"
  assert_file_exists "${PREFIX_MAN}/${cmd}.1" "isolated install installs man page for ${cmd}"
done
assert_file_exists "${PREFIX_LIB}/common.sh" "isolated install installs shared common.sh"
assert_file_exists "${PREFIX_LIB}/VERSION" "isolated install installs VERSION into lib dir"
assert_file_exists "${PREFIX_BASH}/millennium-helpers" "isolated install installs bash completion base"
assert_file_exists "${PREFIX_ZSH}/_millennium-helpers" "isolated install installs zsh completion base"
assert_file_exists "${PREFIX_NU}/millennium-helpers.nu" "isolated install installs nushell completions"
if [[ "$(uname)" != "Darwin" ]]; then
  assert_file_exists "$PREFIX_SUDOERS" "isolated install writes sudoers file"
else
  assert_file_not_exists "$PREFIX_SUDOERS" "isolated install skips sudoers on macOS"
fi

# Smoke: installed script resolves shared lib via prefix-relative path
out=$("${PREFIX_BIN}/millennium-diag" --help 2>&1)
rc=$?
assert_success "$rc" "installed millennium-diag --help works against prefix lib"
assert_contains "$out" "Usage:" "installed millennium-diag --help prints usage"

out=$(
  TARGET_DIR="$PREFIX_BIN" \
  MILLENNIUM_LIB_DIR="$PREFIX_LIB" \
  MILLENNIUM_BASH_COMPLETION_DIR="$PREFIX_BASH" \
  MILLENNIUM_ZSH_COMPLETION_DIR="$PREFIX_ZSH" \
  MILLENNIUM_FISH_COMPLETION_DIR="$PREFIX_FISH" \
  MILLENNIUM_NUSHELL_COMPLETION_DIR="$PREFIX_NU" \
  MILLENNIUM_MAN_DIR="$PREFIX_MAN" \
  MOCK_SUDOERS_FILE="$PREFIX_SUDOERS" \
  SUDO_USER="installtestuser" \
  bash "$INSTALL_SH" uninstall < /dev/null 2>&1
)
rc=$?
assert_success "$rc" "install.sh uninstall from isolated prefix exits 0"
assert_contains "$out" "Disabling update scheduler" "isolated uninstall disables the scheduler"

for cmd in millennium millennium-repair millennium-upgrade millennium-schedule \
           millennium-purge millennium-diag millennium-theme millennium-mcp; do
  assert_file_not_exists "${PREFIX_BIN}/${cmd}" "isolated uninstall removes ${cmd}"
  assert_file_not_exists "${PREFIX_BASH}/${cmd}" "isolated uninstall removes bash completion for ${cmd}"
  assert_file_not_exists "${PREFIX_ZSH}/_${cmd}" "isolated uninstall removes zsh completion for ${cmd}"
  assert_file_not_exists "${PREFIX_FISH}/${cmd}.fish" "isolated uninstall removes fish completion for ${cmd}"
  assert_file_not_exists "${PREFIX_MAN}/${cmd}.1" "isolated uninstall removes man page for ${cmd}"
done
assert_file_not_exists "${PREFIX_LIB}/common.sh" "isolated uninstall removes shared lib"
assert_file_not_exists "${PREFIX_BASH}/millennium-helpers" "isolated uninstall removes bash completion base"
assert_file_not_exists "${PREFIX_ZSH}/_millennium-helpers" "isolated uninstall removes zsh completion base"
assert_file_not_exists "${PREFIX_NU}/millennium-helpers.nu" "isolated uninstall removes nushell completions"
if [[ "$(uname)" != "Darwin" ]]; then
  assert_file_not_exists "$PREFIX_SUDOERS" "isolated uninstall removes sudoers file"
fi

rm -rf "$PREFIX"
rm -f "${MOCK_BIN}/id" "${MOCK_BIN}/visudo" "${MOCK_BIN}/chown" "${MOCK_BIN}/systemctl" "${MOCK_BIN}/crontab"

# --- Packaging inventory: Formula / PKGBUILD / Scoop keep install parity ---

formula=$(cat "${REPO_ROOT}/Formula/millennium-helpers.rb")
assert_contains "$formula" 'ln_sf "millennium-helpers", bash_completion/cmd' "Formula creates bash completion symlinks"
assert_contains "$formula" 'ln_sf "_millennium-helpers", zsh_completion/"_#{cmd}"' "Formula creates zsh completion symlinks"
assert_contains "$formula" 'share/"nushell/completions"' "Formula installs nushell completions"
assert_contains "$formula" 'assert_path_exists bash_completion/"millennium"' "Formula test checks millennium bash completion"

pkgbuild=$(cat "${REPO_ROOT}/packaging/millennium-helpers-git/PKGBUILD")
assert_contains "$pkgbuild" "/usr/local/bin/millennium " "PKGBUILD prepare mentions bare millennium binary"
assert_contains "$pkgbuild" "millennium.fish" "PKGBUILD prepare mentions millennium.fish"
stable_pkgbuild=$(cat "${REPO_ROOT}/packaging/millennium-helpers/PKGBUILD")
assert_contains "$stable_pkgbuild" "millennium-helpers-linux.tar.gz" "versioned PKGBUILD uses Linux release tarball"
assert_contains "$stable_pkgbuild" "conflicts=(" "versioned PKGBUILD declares conflicts"

scoop=$(cat "${REPO_ROOT}/packaging/scoop/millennium-helpers.json")
assert_contains "$scoop" "post_install" "Scoop manifest registers post_install hooks"
assert_contains "$scoop" "pre_uninstall" "Scoop manifest registers pre_uninstall hooks"
assert_contains "$scoop" "millennium-helpers.ps1" "Scoop post_install wires PowerShell completions"
assert_contains "$scoop" "MillenniumUpdate" "Scoop pre_uninstall removes MillenniumUpdate task"
scoop_git=$(cat "${REPO_ROOT}/packaging/scoop/millennium-helpers-git.json")
assert_contains "$scoop_git" '"version": "nightly"' "Scoop git manifest uses nightly version"
assert_contains "$scoop_git" "archive/refs/heads/main.zip" "Scoop git manifest uses main branch archive"
assert_contains "$scoop_git" "millenium-helpers-main" "Scoop git manifest sets extract_dir for GitHub archive"
assert_contains "$scoop_git" "post_install" "Scoop git manifest registers post_install hooks"

print_summary
