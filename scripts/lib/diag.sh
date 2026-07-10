# shellcheck shell=bash
# Diagnostic library loader for millennium-diag.sh
# Thin aggregator — implementation lives in diag_*.sh modules.
# Status flags below are read by millennium-diag.sh (JSON output / doctor).
# shellcheck disable=SC2034

_diag_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=diag_ui.sh
source "${_diag_lib_dir}/diag_ui.sh"
# shellcheck source=diag_steam.sh
source "${_diag_lib_dir}/diag_steam.sh"
# shellcheck source=diag_env.sh
source "${_diag_lib_dir}/diag_env.sh"
# shellcheck source=diag_install.sh
source "${_diag_lib_dir}/diag_install.sh"
# shellcheck source=diag_release.sh
source "${_diag_lib_dir}/diag_release.sh"
# shellcheck source=diag_updates.sh
source "${_diag_lib_dir}/diag_updates.sh"
# shellcheck source=diag_completions.sh
source "${_diag_lib_dir}/diag_completions.sh"
# shellcheck source=diag_package_files.sh
source "${_diag_lib_dir}/diag_package_files.sh"
# shellcheck source=diag_next_steps.sh
source "${_diag_lib_dir}/diag_next_steps.sh"
# shellcheck source=diag_doctor_cleanup.sh
source "${_diag_lib_dir}/diag_doctor_cleanup.sh"
# shellcheck source=diag_doctor_scripts.sh
source "${_diag_lib_dir}/diag_doctor_scripts.sh"
# shellcheck source=diag_doctor_repair.sh
source "${_diag_lib_dir}/diag_doctor_repair.sh"
# shellcheck source=diag_doctor_completions.sh
source "${_diag_lib_dir}/diag_doctor_completions.sh"
# shellcheck source=diag_doctor.sh
source "${_diag_lib_dir}/diag_doctor.sh"

unset _diag_lib_dir

run_diagnostics() {
  echo -e "${BLUE}=== Millennium Diagnostics Report ===${NC}\n"

  check_steam_status
  check_binaries_integrity
  check_bootstrap_hooks
  check_directory_permissions
  check_sudoers_authorization
  check_scheduler_status
  check_install_method
  check_helper_updates
  check_shell_completions
  check_unmanaged_package_files
  check_obsolete_files
}
