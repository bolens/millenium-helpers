#!/usr/bin/env bash
# Millennium Helpers local test runner
# Thin orchestrator: syntax checks + unit/behavioral suites.
# Feature/CLI coverage: make test-go / go.yml. Packaging/Homebrew/Winget: dedicated CI.
set -euo pipefail

THIS_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${THIS_TEST_DIR}/.." && pwd)"

# shellcheck source=lib/assertions.sh
source "${THIS_TEST_DIR}/lib/assertions.sh"

# 1. Syntax Validation
echo -e "${YELLOW}Running syntax validations...${NC}"
for script in "${REPO_ROOT}"/scripts/*.sh "${REPO_ROOT}"/install.sh; do
  [[ -f "$script" ]] || continue
  tests_run=$((tests_run + 1))
  if bash -n "$script"; then
    echo -e "  ${GREEN}PASS:${NC} Syntax check for ${script#"$REPO_ROOT"/}"
  else
    echo -e "  ${RED}FAIL:${NC} Syntax check for ${script#"$REPO_ROOT"/}" >&2
    tests_failed=$((tests_failed + 1))
  fi
done

# 2. Unit & behavioral test suites
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
    echo -e "  ${RED}FAIL:${NC} ${suite_name} exited without reporting a subtotal (rc=${suite_rc})" >&2
    tests_run=$((tests_run + 1))
    tests_failed=$((tests_failed + 1))
    suite_failed_files+=("$suite_name")
  fi
done

# 3. Lightweight packaging version sync (full packaging gates are in CI)
echo -e "\n${YELLOW}Running packaging version sync check...${NC}"
tests_run=$((tests_run + 1))
if bash "${REPO_ROOT}/scripts/ci/check-version-sync.sh"; then
  echo -e "  ${GREEN}PASS:${NC} packaging versions match VERSION"
else
  echo -e "  ${RED}FAIL:${NC} packaging versions match VERSION" >&2
  tests_failed=$((tests_failed + 1))
fi

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
