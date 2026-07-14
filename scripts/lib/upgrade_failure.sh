# shellcheck shell=bash
# Upgrade failure trap for millennium-upgrade.sh

failure_handler() {
  local exit_code=$?
  if [[ "$DRY_RUN" == "false" ]]; then
    send_notification "Millennium Update Failed" "An error occurred during the update process (exit code: $exit_code)."
    print_upgrade_failure_tips "$exit_code"
  fi
}
