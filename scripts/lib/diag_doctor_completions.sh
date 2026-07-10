# shellcheck shell=bash
# shellcheck disable=SC2154 # globals initialized by millennium-diag.sh before doctor runs
# Doctor shell-completion restore from release tarball
doctor_repair_completions() {
# Issue 10: Missing or out-of-date completions
if [[ "$COMPLETIONS_OK" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Repairing shell autocompletions...${NC}"

  if [[ "$INSTALL_METHOD" == "pacman" ]] || helpers_are_pacman_packaged; then
    echo -e "Helpers are installed via pacman. Skipping direct writes under /usr/share."
    echo -e "Reinstall the package after clearing unmanaged leftovers:"
    print_package_upgrade_hint
  else
    if [[ -z "${DIAG_RELEASE_EXTRACT:-}" || ! -d "${DIAG_RELEASE_EXTRACT}" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "[DRY RUN] Would download latest release tarball for completions"
      else
        fetch_latest_release_tag || true
        diag_fetch_release_tarball || true
      fi
    fi

    for local_path in ${missing_completions[@]+"${missing_completions[@]}"} ${out_of_date_completions[@]+"${out_of_date_completions[@]}"}; do
      [[ -n "$local_path" ]] || continue
      remote_rel="$(diag_completion_remote_for "$local_path" || true)"
      if [[ -z "$remote_rel" ]]; then
        echo -e "${YELLOW}Warning: no remote mapping for ${local_path}; skipping.${NC}"
        continue
      fi
      release_src=""
      if [[ -n "${DIAG_RELEASE_EXTRACT:-}" ]]; then
        release_src="$(_diag_release_source_path "$remote_rel" || true)"
      fi
      echo "Restoring completion file: $local_path"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "[DRY RUN] Would install ${remote_rel} to $local_path"
      elif [[ -n "$release_src" && -f "$release_src" ]]; then
        execute install -m644 "$release_src" "$local_path"
      else
        remote_url="https://raw.githubusercontent.com/bolens/millenium-helpers/${LATEST_RELEASE_TAG:-main}/${remote_rel}"
        execute curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 3 --retry-delay 2 "$remote_url" -o "$local_path"
        execute chmod 644 "$local_path"
      fi
    done

    for symlink_item in ${broken_symlinks[@]+"${broken_symlinks[@]}"}; do
      [[ -n "$symlink_item" ]] || continue
      symlink_path="${symlink_item%%:*}"
      symlink_target="${symlink_item#*:}"
      echo "Restoring symlink: $symlink_path -> $symlink_target"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "[DRY RUN] Would link $symlink_path to $symlink_target"
      else
        execute rm -f "$symlink_path"
        execute ln -sf "$symlink_target" "$symlink_path"
      fi
    done
  fi
fi

}
