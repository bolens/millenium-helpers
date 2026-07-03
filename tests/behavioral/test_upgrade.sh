#!/usr/bin/env bash
# Behavioral tests shared by millennium-upgrade-stable.sh and millennium-upgrade-beta.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

mock_cmd "pgrep" 'exit 1'  # Steam not running, for most tests

echo -e "${YELLOW}=== Behavioral tests: millennium-upgrade-stable.sh & millennium-upgrade-beta.sh ===${NC}"

# run_upgrade <stable|beta> [args...]
run_upgrade() {
  local channel="$1"; shift
  bash "${REPO_ROOT}/scripts/millennium-upgrade-${channel}.sh" "$@"
}

for channel in stable beta; do
  script_name="millennium-upgrade-${channel}.sh"

  # --- Unknown option ---
  out=$(run_upgrade "$channel" --bogus 2>&1)
  rc=$?
  assert_failure "$rc" "${script_name} exits non-zero on an unknown option"
  assert_contains "$out" "Unknown option" "${script_name} reports the unrecognized option"

  # --- Network offline aborts immediately ---
  mock_cmd "curl" 'exit 1'
  out=$(run_upgrade "$channel" --dry-run 2>&1)
  rc=$?
  assert_failure "$rc" "${script_name} --dry-run aborts when the network is unreachable"
  assert_contains "$out" "Network is offline" "${script_name} explains the network is offline"
  rm -f "${MOCK_BIN}/curl"

  # --- GitHub tag fetch failure surfaces a clear error ---
  # shellcheck disable=SC2016
  mock_cmd "curl" '
for arg in "$@"; do
  if [[ "$arg" == "https://github.com" ]]; then exit 0; fi
done
echo "null"
'
  out=$(run_upgrade "$channel" --dry-run 2>&1)
  rc=$?
  assert_failure "$rc" "${script_name} --dry-run fails cleanly when no release tag can be resolved"
  assert_contains "$out" "Could not retrieve the latest" "${script_name} explains it could not retrieve a version tag"
  rm -f "${MOCK_BIN}/curl"

  # --- --file: Offline archive installation ---
  MOCK_FILE=$(mktemp)
  echo "mock archive content" > "$MOCK_FILE"
  out=$(run_upgrade "$channel" --file "$MOCK_FILE" --dry-run 2>&1)
  rc=$?
  assert_success "$rc" "${script_name} with --file and --dry-run exits 0"
  assert_contains "$out" "Would install local archive" "${script_name} --file notices local installation"
  rm -f "$MOCK_FILE"

  # --- Backup Management & Pruning & Rollback ---
  TEST_LIB_DIR=$(mktemp -d)
  export MOCK_LIB_DIR="${TEST_LIB_DIR}"

  # Create mock backups
  mkdir -p "${TEST_LIB_DIR}/millennium.bak_v2.0.0"
  mkdir -p "${TEST_LIB_DIR}/millennium.bak_v2.1.0"
  mkdir -p "${TEST_LIB_DIR}/millennium.bak_v2.2.0"
  
  # 1. Rollback list command
  out=$(run_upgrade "$channel" --rollback list 2>&1)
  rc=$?
  assert_success "$rc" "${script_name} --rollback list exits 0"
  assert_contains "$out" "v2.0.0" "${script_name} --rollback list lists v2.0.0"
  assert_contains "$out" "v2.1.0" "${script_name} --rollback list lists v2.1.0"
  assert_contains "$out" "v2.2.0" "${script_name} --rollback list lists v2.2.0"

  # 2. Rollback to specific target (dry-run)
  out=$(run_upgrade "$channel" --rollback v2.1.0 --dry-run 2>&1)
  rc=$?
  assert_success "$rc" "${script_name} --rollback target --dry-run exits 0"
  assert_contains "$out" "Would swap active version with backup ${TEST_LIB_DIR}/millennium.bak_v2.1.0" "${script_name} rolls back to specified version"

  # 3. Pruning check (dry-run)
  export CONFIG_BACKUP_LIMIT=2
  MOCK_FILE2=$(mktemp)
  echo "mock archive" > "$MOCK_FILE2"
  out=$(run_upgrade "$channel" --file "$MOCK_FILE2" --dry-run 2>&1)
  rc=$?
  assert_success "$rc" "${script_name} with custom backup limit exits 0"
  assert_contains "$out" "Would prune backup: ${TEST_LIB_DIR}/millennium.bak_v2.0.0" "${script_name} prunes the oldest backup exceeding the limit"

  rm -f "$MOCK_FILE2"
  rm -rf "$TEST_LIB_DIR"
  unset MOCK_LIB_DIR
  unset CONFIG_BACKUP_LIMIT

done

# --- Full happy-path dry-run for stable, with mocked network/tag/checksum ---

# shellcheck disable=SC2016
mock_cmd "curl" '
for arg in "$@"; do
  if [[ "$arg" == "https://github.com" ]]; then exit 0; fi
done
url="${@: -1}"
case "$url" in
  *releases/latest*) echo "{\"tag_name\": \"v9.9.9\"}" ;;
  *.sha256) echo "deadbeefcafef00d1234567890abcdef1234567890abcdef1234567890abcd  millennium-v9.9.9-linux-x86_64.tar.gz" ;;
  *) echo "" ;;
esac
'
out=$(run_upgrade stable --dry-run 2>&1)
rc=$?
assert_success "$rc" "millennium-upgrade-stable.sh --dry-run completes successfully with a mocked network/API"
assert_contains "$out" "v9.9.9" "millennium-upgrade-stable.sh --dry-run resolves and reports the fetched version"
assert_contains "$out" "deadbeefcafef00d" "millennium-upgrade-stable.sh --dry-run reports the expected SHA256 checksum"
assert_contains "$out" "Dry run completed successfully" "millennium-upgrade-stable.sh --dry-run reports overall success"

# --- Already up-to-date short-circuit (no --force) ---
# The real /usr/lib/millennium/version.txt reflects whatever happens to be
# installed on the test machine (if anything). We read it dynamically so the
# test is robust regardless of what's actually installed, rather than assuming
# a specific version or requiring root to fake one.

if [[ -f /usr/lib/millennium/version.txt ]]; then
  installed_ver=$(cat /usr/lib/millennium/version.txt)
  mock_cmd "curl" "
for arg in \"\$@\"; do
  if [[ \"\$arg\" == 'https://github.com' ]]; then exit 0; fi
done
echo '{\"tag_name\": \"v${installed_ver}\"}'
"
  out=$(run_upgrade stable --dry-run 2>&1)
  rc=$?
  assert_success "$rc" "millennium-upgrade-stable.sh --dry-run exits 0 when already at the latest version"
  assert_contains "$out" "already up to date" "millennium-upgrade-stable.sh --dry-run reports it is already up to date (no --force)"
  rm -f "${MOCK_BIN}/curl"

  # --force bypasses the short-circuit and proceeds to fetch the checksum
  mock_cmd "curl" "
for arg in \"\$@\"; do
  if [[ \"\$arg\" == 'https://github.com' ]]; then exit 0; fi
done
url=\"\${@: -1}\"
case \"\$url\" in
  *releases/latest*) echo '{\"tag_name\": \"v${installed_ver}\"}' ;;
  *.sha256) echo 'deadbeefcafef00d1234567890abcdef1234567890abcdef1234567890abcd  millennium-v${installed_ver}-linux-x86_64.tar.gz' ;;
  *) echo '' ;;
esac
"
  out=$(run_upgrade stable --force --dry-run 2>&1)
  rc=$?
  assert_success "$rc" "millennium-upgrade-stable.sh --dry-run --force exits 0 even when already up to date"
  assert_not_contains "$out" "already up to date" "millennium-upgrade-stable.sh --dry-run --force bypasses the up-to-date short-circuit"
  assert_contains "$out" "Would download archive" "millennium-upgrade-stable.sh --dry-run --force proceeds to the download step"
  rm -f "${MOCK_BIN}/curl"
fi

print_summary
