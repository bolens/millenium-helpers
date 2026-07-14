# shellcheck shell=bash
# Network readiness check for millennium-upgrade.sh

check_network() {
  local retries=5
  local wait_sec="${MOCK_NETWORK_WAIT_SEC:-10}"
  echo "Checking network connectivity..."
  for ((i=1; i<=retries; i++)); do
    if curl -sIk "https://github.com" &>/dev/null; then
      return 0
    fi
    echo "Network offline, retrying in ${wait_sec}s ($i/$retries)..." >&2
    if [[ "$wait_sec" -gt 0 ]]; then
      sleep "$wait_sec"
    fi
  done
  echo "Error: Network is offline. Aborting." >&2
  exit 1
}
