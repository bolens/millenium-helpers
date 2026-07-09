#!/usr/bin/env bash
# Mock command helpers for the Millennium Helpers test suite.
# Provides an isolated directory prepended to $PATH so tests can stub out
# external commands (curl, jq, systemctl, runuser, getent, etc.) with
# deterministic, side-effect-free fakes.

# Creates a fresh mock bin directory and prepends it to PATH.
# Call once per test file; the trap cleans it up on exit.
setup_mock_bin() {
  MOCK_BIN=$(mktemp -d)
  export MOCK_BIN
  export PATH="${MOCK_BIN}:${PATH}"
  export MOCK_PROC="/nonexistent_mock_proc"

  # Stub out process-killing and Steam commands by default to protect the host environment
  mock_cmd "killall" "exit 0"
  mock_cmd "pkill" "exit 0"
  mock_cmd "pgrep" "exit 1"
  mock_cmd "runuser" "exit 0"
  mock_cmd "steam" "exit 0"
  mock_cmd "systemctl" "exit 0"
  mock_cmd "launchctl" "exit 0"
  mock_cmd "crontab" "exit 0"
  mock_cmd "osascript" "exit 0"
  mock_cmd "notify-send" "exit 0"
  mock_cmd "visudo" "exit 0"
  mock_cmd "open" "exit 0"
  export TEST_SUITE_RUN=true
}

teardown_mock_bin() {
  [[ -n "${MOCK_BIN:-}" ]] && rm -rf "${MOCK_BIN}"
}

# mock_cmd <name> <script body>
# Writes an executable script named <name> into MOCK_BIN so it shadows the
# real command via PATH lookup. Body is written verbatim as a bash script.
mock_cmd() {
  local name="$1"
  local body="$2"
  cat > "${MOCK_BIN}/${name}" << MOCKEOF
#!/usr/bin/env bash
${body}
MOCKEOF
  chmod +x "${MOCK_BIN}/${name}"
}

# mock_cmd_output <name> <fixed stdout> [<exit code>]
# Convenience for the common "just print this and exit N" case.
mock_cmd_output() {
  local name="$1"
  local output="$2"
  local code="${3:-0}"
  mock_cmd "$name" "cat << 'OUTPUTEOF'
${output}
OUTPUTEOF
exit ${code}"
}
