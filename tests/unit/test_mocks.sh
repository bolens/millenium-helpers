#!/usr/bin/env bash
# Unit tests for mocks.sh
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Unit tests: mocks.sh ===${NC}"

# Test mocking a normal command
mock_cmd "dummy_test_cmd" "echo 'hello from dummy'"
out=$(dummy_test_cmd)
assert_equals "hello from dummy" "$out" "mock_cmd successfully stubs a custom command"

# Test mocking chmod itself (prevent self-shadowing bug)
mock_cmd "chmod" "echo 'chmod mock run'; exit 0"
mock_cmd "subsequent_cmd" "echo 'subsequent success'"
out=$(subsequent_cmd)
assert_equals "subsequent success" "$out" "mock_cmd can successfully mock subsequent commands even after chmod is mocked"

# Test unmocking a command
unmock_cmd "subsequent_cmd"
which subsequent_cmd &>/dev/null
rc=$?
assert_not_equals "0" "$rc" "unmock_cmd successfully removes custom command shadow"

# Test mock_cmd_output helper
mock_cmd_output "output_test_cmd" "static text" 42
out=$(output_test_cmd 2>&1)
rc=$?
assert_equals "static text" "$out" "mock_cmd_output prints expected stdout"
assert_equals "42" "$rc" "mock_cmd_output returns expected exit code"

# Host-protection defaults: without these, local suite runs can close/relaunch
# the developer's real Steam client (or kill processes via killall/pkill).
assert_equals "true" "${TEST_SUITE_RUN:-}" "setup_mock_bin exports TEST_SUITE_RUN=true"
for host_cmd in steam pgrep runuser killall pkill; do
  assert_file_exists "${MOCK_BIN}/${host_cmd}" "setup_mock_bin stubs ${host_cmd} to protect the host"
done

print_summary
