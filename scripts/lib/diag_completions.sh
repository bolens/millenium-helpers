# shellcheck shell=bash
# shellcheck disable=SC2034 # status globals read by millennium-diag.sh / doctor
# Shell completion presence and version checks
check_shell_completions() {
  if [[ -n "${DIAG_TEST_BYPASS_CHECKS:-}" ]]; then
    COMPLETIONS_OK=true
    return
  fi
  echo -e "\nShell Autocompletions Status:"

  DIAG_COMPLETION_PATHS=(
    "/usr/share/bash-completion/completions/millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-helpers"
    "/usr/share/fish/vendor_completions.d/millennium.fish"
    "/usr/share/fish/vendor_completions.d/millennium-repair.fish"
    "/usr/share/fish/vendor_completions.d/millennium-upgrade.fish"
    "/usr/share/fish/vendor_completions.d/millennium-schedule.fish"
    "/usr/share/fish/vendor_completions.d/millennium-purge.fish"
    "/usr/share/fish/vendor_completions.d/millennium-diag.fish"
    "/usr/share/fish/vendor_completions.d/millennium-theme.fish"
    "/usr/share/fish/vendor_completions.d/millennium-mcp.fish"
  )
  DIAG_COMPLETION_REPOS=(
    "completions/bash/millennium-helpers"
    "completions/zsh/_millennium-helpers"
    "completions/fish/millennium.fish"
    "completions/fish/millennium-repair.fish"
    "completions/fish/millennium-upgrade.fish"
    "completions/fish/millennium-schedule.fish"
    "completions/fish/millennium-purge.fish"
    "completions/fish/millennium-diag.fish"
    "completions/fish/millennium-theme.fish"
    "completions/fish/millennium-mcp.fish"
  )

  local nu_dest=""
  for base_dir in "/usr/share" "/usr/local/share"; do
    if [[ -d "${base_dir}/nushell/completions" ]]; then
      nu_dest="${base_dir}/nushell/completions/millennium-helpers.nu"
      break
    fi
  done
  if [[ -z "$nu_dest" ]]; then
    nu_dest="/usr/share/nushell/completions/millennium-helpers.nu"
  fi
  DIAG_COMPLETION_PATHS+=("$nu_dest")
  DIAG_COMPLETION_REPOS+=("completions/nushell/millennium-helpers.nu")

  declare -a COMPLETION_SYMLINKS=(
    "/usr/share/bash-completion/completions/millennium:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-repair:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-upgrade:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-schedule:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-purge:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-diag:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-theme:millennium-helpers"
    "/usr/share/bash-completion/completions/millennium-mcp:millennium-helpers"

    "/usr/share/zsh/site-functions/_millennium:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-repair:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-upgrade:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-schedule:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-purge:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-diag:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-theme:_millennium-helpers"
    "/usr/share/zsh/site-functions/_millennium-mcp:_millennium-helpers"
  )

  missing_completions=()
  out_of_date_completions=()

  local packaged=false
  if [[ "$INSTALL_METHOD" == "pacman" ]] || helpers_are_pacman_packaged; then
    packaged=true
  fi

  local i local_path remote_rel local_dir release_path tmp_dest local_sha remote_sha
  for i in "${!DIAG_COMPLETION_PATHS[@]}"; do
    local_path="${DIAG_COMPLETION_PATHS[$i]}"
    remote_rel="${DIAG_COMPLETION_REPOS[$i]}"
    local_dir=$(dirname "$local_path")
    [[ -d "$local_dir" ]] || continue

    if [[ ! -f "$local_path" ]]; then
      COMPLETIONS_OK=false
      missing_completions+=("$local_path")
      print_diag_item "error" "  - $(basename "$local_path")" "Missing"
    elif [[ "$packaged" == "true" ]]; then
      print_diag_item "ok" "  - $(basename "$local_path")" "Present (pacman package)"
    elif [[ "${ONLINE:-false}" != "true" ]]; then
      print_diag_item "ok" "  - $(basename "$local_path")" "Present (offline, cannot verify version)"
    else
      release_path="$(_diag_release_source_path "$remote_rel")"
      tmp_dest="${TMP_SCRIPTS:-}/comp_$(basename "$local_path")"
      if [[ -z "$release_path" ]]; then
        if [[ -z "${TMP_SCRIPTS:-}" || ! -d "$TMP_SCRIPTS" ]]; then
          TMP_SCRIPTS=$(mktemp -d)
          trap 'rm -rf "${TMP_SCRIPTS:-}"; _diag_cleanup_release_workdir' EXIT INT TERM
        fi
        if ! _diag_fetch_remote_to_tmp "$remote_rel" "$tmp_dest"; then
          print_diag_item "warn" "  - $(basename "$local_path")" "Unable to check (HTTP download failed)"
          continue
        fi
        release_path="$tmp_dest"
      fi

      local_sha="$(_diag_file_sha256 "$local_path")"
      remote_sha="$(_diag_file_sha256 "$release_path")"
      if [[ -n "$local_sha" && -n "$remote_sha" && "$local_sha" == "$remote_sha" ]]; then
        print_diag_item "ok" "  - $(basename "$local_path")" "Up to date (${LATEST_RELEASE_TAG:-release})"
      else
        COMPLETIONS_OK=false
        out_of_date_completions+=("$local_path")
        print_diag_item "error" "  - $(basename "$local_path")" "Out of date"
      fi
    fi
  done

  broken_symlinks=()
  for symlink_item in "${COMPLETION_SYMLINKS[@]}"; do
    local symlink_path="${symlink_item%%:*}"
    local symlink_target="${symlink_item#*:}"
    local symlink_dir
    symlink_dir=$(dirname "$symlink_path")
    [[ -d "$symlink_dir" ]] || continue

    if [[ ! -L "$symlink_path" ]]; then
      COMPLETIONS_OK=false
      broken_symlinks+=("$symlink_path:$symlink_target")
      print_diag_item "error" "  - $(basename "$symlink_path") symlink" "Missing/Broken"
    else
      local target_resolved
      target_resolved=$(readlink "$symlink_path" || true)
      if [[ "$target_resolved" != "$symlink_target" ]]; then
        COMPLETIONS_OK=false
        broken_symlinks+=("$symlink_path:$symlink_target")
        print_diag_item "error" "  - $(basename "$symlink_path") symlink" "Incorrect target (${target_resolved})"
      fi
    fi
  done
}

