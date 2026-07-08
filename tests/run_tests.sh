#!/usr/bin/env bash
# Millennium Helpers Unit Test Suite
set -euo pipefail

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

tests_run=0
tests_failed=0

assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-Assertion failed}"
  tests_run=$((tests_run + 1))
  if [[ "$expected" != "$actual" ]]; then
    echo -e "  ${RED}FAIL:${NC} ${msg} (Expected: '${expected}', Got: '${actual}')" >&2
    tests_failed=$((tests_failed + 1))
    return 1
  fi
  echo -e "  ${GREEN}PASS:${NC} ${msg}"
  return 0
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-Assertion failed}"
  tests_run=$((tests_run + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    echo -e "  ${RED}FAIL:${NC} ${msg} (Expected '${haystack}' to contain '${needle}')" >&2
    tests_failed=$((tests_failed + 1))
    return 1
  fi
  echo -e "  ${GREEN}PASS:${NC} ${msg}"
  return 0
}

# 1. Syntax Validation
echo -e "${YELLOW}Running syntax validations...${NC}"
for script in scripts/*.sh install.sh; do
  tests_run=$((tests_run + 1))
  if bash -n "$script"; then
    echo -e "  ${GREEN}PASS:${NC} Syntax check for ${script}"
  else
    echo -e "  ${RED}FAIL:${NC} Syntax check for ${script}" >&2
    tests_failed=$((tests_failed + 1))
  fi
done

# 2. Unit Testing common.sh
echo -e "\n${YELLOW}Running unit tests for common.sh...${NC}"

# Source the helpers to test them
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts"
export DRY_RUN=true # Keep dry-run active during unit tests
export MOCK_PROC="/nonexistent_mock_proc"

# Mocking resolve_helper_path environment
# Create a temp bin directory with mock scripts
MOCK_BIN=$(mktemp -d)
trap 'rm -rf "$MOCK_BIN"' EXIT

touch "${MOCK_BIN}/millennium-diag"
chmod +x "${MOCK_BIN}/millennium-diag"

# Source common.sh
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/common.sh"

# Test resolve_helper_path with mock
# Temporarily modify PATH to find mock script
OLD_PATH="$PATH"
export PATH="${MOCK_BIN}:$PATH"
resolved=$(resolve_helper_path "millennium-diag")
assert_equals "${MOCK_BIN}/millennium-diag" "$resolved" "resolve_helper_path resolves scripts from PATH"
export PATH="$OLD_PATH"

# Test logging output formats
log_output=$(log_info "Test Message")
assert_contains "$log_output" "[INFO]" "log_info contains INFO severity tag"
assert_contains "$log_output" "Test Message" "log_info contains correct message text"

log_err_output=$(log_error "Error Message" 2>&1)
assert_contains "$log_err_output" "[ERROR]" "log_error contains ERROR severity tag"
assert_contains "$log_err_output" "Error Message" "log_error contains correct message text"

# Test execute function in dry-run mode
exec_output=$(execute echo "hello world")
assert_contains "$exec_output" "[DRY RUN]" "execute wrapper outputs dry-run notice"
assert_contains "$exec_output" "echo hello world" "execute wrapper outputs command arguments"

# 3. Unit & behavioral test suites (tests/unit/*.sh, tests/behavioral/*.sh)
# Each of these is a standalone executable script with its own assertion
# framework (tests/lib/assertions.sh + tests/lib/mocks.sh). It exits 0/1 based
# on its own pass/fail state and prints a final "SUBTOTAL file=... run=N
# failed=M" line, which we parse here to fold its results into the grand
# total. Each suite runs in its own subshell/process so a failure or stray
# `exit` in one file cannot abort the rest of the run.
THIS_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite_failed_files=()

for suite in "${THIS_TEST_DIR}"/unit/*.sh "${THIS_TEST_DIR}"/behavioral/*.sh; do
  [[ -f "$suite" ]] || continue
  suite_name="$(basename "$suite")"
  echo -e "\n${YELLOW}Running suite: ${suite_name}...${NC}"

  suite_output=$(bash "$suite" 2>&1) && suite_rc=0 || suite_rc=$?
  echo "$suite_output"

  subtotal_line=$(echo "$suite_output" | grep -E '^SUBTOTAL file=' | tail -n1)
  if [[ -n "$subtotal_line" ]]; then
    suite_run=0
    suite_fail=0
    if [[ "$subtotal_line" =~ run=([0-9]+) ]]; then
      suite_run="${BASH_REMATCH[1]}"
    fi
    if [[ "$subtotal_line" =~ failed=([0-9]+) ]]; then
      suite_fail="${BASH_REMATCH[1]}"
    fi
    tests_run=$((tests_run + suite_run))
    tests_failed=$((tests_failed + suite_fail))
    if [[ "$suite_fail" -ne 0 ]]; then
      suite_failed_files+=("$suite_name")
    fi
  else
    # Suite didn't emit a subtotal line (e.g. crashed before print_summary) -
    # count it as a single failing test so it isn't silently dropped.
    echo -e "  ${RED}FAIL:${NC} ${suite_name} exited without reporting a subtotal (rc=${suite_rc})" >&2
    tests_run=$((tests_run + 1))
    tests_failed=$((tests_failed + 1))
    suite_failed_files+=("$suite_name")
  fi
done

# Summary
echo -e "\n${YELLOW}=== Test Suite Summary ===${NC}"
echo -e "Total Tests Run: ${tests_run}"
if [[ "$tests_failed" -eq 0 ]]; then
  echo -e "${GREEN}All tests passed successfully!${NC}"
  exit 0
else
  echo -e "${RED}${tests_failed} test(s) failed.${NC}"
  if [[ ${#suite_failed_files[@]} -gt 0 ]]; then
    echo -e "${RED}Failing suites: ${suite_failed_files[*]}${NC}"
  fi
  exit 1
fi
