#!/usr/bin/env bash
# Shared assertion helpers for the Millennium Helpers test suite.
# Source this file from each test_*.sh file. Each test file keeps its own
# tests_run/tests_failed counters and calls print_summary at the end.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

tests_run=0
tests_failed=0

_report() {
  local ok="$1"
  local msg="$2"
  local detail="${3:-}"
  tests_run=$((tests_run + 1))
  if [[ "$ok" == "true" ]]; then
    echo -e "  ${GREEN}PASS:${NC} ${msg}"
  else
    tests_failed=$((tests_failed + 1))
    echo -e "  ${RED}FAIL:${NC} ${msg}${detail:+ (${detail})}" >&2
  fi
}

assert_equals() {
  local expected="$1" actual="$2" msg="${3:-Assertion failed}"
  if [[ "$expected" == "$actual" ]]; then
    _report true "$msg"
  else
    _report false "$msg" "Expected: '${expected}', Got: '${actual}'"
  fi
}

assert_not_equals() {
  local not_expected="$1" actual="$2" msg="${3:-Assertion failed}"
  if [[ "$not_expected" != "$actual" ]]; then
    _report true "$msg"
  else
    _report false "$msg" "Did not expect: '${actual}'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-Assertion failed}"
  if [[ "$haystack" == *"$needle"* ]]; then
    _report true "$msg"
  else
    _report false "$msg" "Expected haystack to contain '${needle}'"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-Assertion failed}"
  if [[ "$haystack" != *"$needle"* ]]; then
    _report true "$msg"
  else
    _report false "$msg" "Expected haystack NOT to contain '${needle}'"
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" msg="${3:-Assertion failed}"
  if [[ "$expected" -eq "$actual" ]]; then
    _report true "$msg"
  else
    _report false "$msg" "Expected exit code ${expected}, got ${actual}"
  fi
}

assert_success() {
  local actual="$1" msg="${2:-Assertion failed}"
  if [[ "$actual" -eq 0 ]]; then
    _report true "$msg"
  else
    _report false "$msg" "Expected exit code 0, got ${actual}"
  fi
}

assert_failure() {
  local actual="$1" msg="${2:-Assertion failed}"
  if [[ "$actual" -ne 0 ]]; then
    _report true "$msg"
  else
    _report false "$msg" "Expected a non-zero exit code, got 0"
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-Assertion failed}"
  if [[ -e "$path" ]]; then
    _report true "$msg"
  else
    _report false "$msg" "Expected file to exist: ${path}"
  fi
}

assert_file_not_exists() {
  local path="$1" msg="${2:-Assertion failed}"
  if [[ ! -e "$path" ]]; then
    _report true "$msg"
  else
    _report false "$msg" "Expected file NOT to exist: ${path}"
  fi
}

assert_valid_json() {
  local json="$1" msg="${2:-Assertion failed}"
  if echo "$json" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
    _report true "$msg"
  else
    _report false "$msg" "Not valid JSON: ${json:0:200}"
  fi
}

# Prints a machine-parsable subtotal line and exits 0/1 accordingly.
# Master runner greps for "SUBTOTAL" lines to compute a grand total.
print_summary() {
  local name
  name="$(basename "${BASH_SOURCE[1]:-$0}")"
  echo -e "\n${YELLOW}--- ${name} summary: ${tests_run} run, ${tests_failed} failed ---${NC}"
  echo "SUBTOTAL file=${name} run=${tests_run} failed=${tests_failed}"
  if [[ "$tests_failed" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}
