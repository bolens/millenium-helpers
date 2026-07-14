# shellcheck shell=bash
# shellcheck disable=SC2154 # globals initialized by millennium-diag.sh before doctor runs
# Doctor repairs for binaries, hooks, Flatpak, sudoers, scheduler, permissions
doctor_repair_runtime() {
# Issue 2: Missing or corrupted binaries
if [[ "$BINARIES_OK" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Repairing Millennium binaries...${NC}"
  echo -e "Invoking updater on the '${UPDATE_CHANNEL}' channel with force reinstall:"
  upgrade_cmd="millennium-upgrade"
  upgrade_path="/usr/local/bin/${upgrade_cmd}"
  if [[ -f "/usr/bin/${upgrade_cmd}" ]]; then
    upgrade_path="/usr/bin/${upgrade_cmd}"
  fi
  execute sudo "${upgrade_path}" --channel "${UPDATE_CHANNEL}" --force
fi

# Issue 3: Missing or broken hooks
if [[ "$HOOKS_OK" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Repairing bootstrap hooks for Steam...${NC}"

  for item in ${broken_hooks[@]+"${broken_hooks[@]}"}; do
    [[ -n "$item" ]] || continue
    sdir="${item%%:*}"
    folder_arch="${item#*:}"
    folder="${folder_arch%%:*}"
    arch="${folder_arch#*:}"
    hook="${sdir}/${folder}/libXtst.so.6"

    echo "Fixing broken hook: $hook"
    execute rm -f "$hook"
    execute ln -sf "/usr/lib/millennium/libmillennium_bootstrap_${arch}.so" "$hook"
  done

  for item in ${missing_hooks[@]+"${missing_hooks[@]}"}; do
    [[ -n "$item" ]] || continue
    sdir="${item%%:*}"
    folder_arch="${item#*:}"
    folder="${folder_arch%%:*}"
    arch="${folder_arch#*:}"
    hook="${sdir}/${folder}/libXtst.so.6"

    echo "Installing missing hook: $hook"
    execute mkdir -p "${sdir}/${folder}"
    execute ln -sf "/usr/lib/millennium/libmillennium_bootstrap_${arch}.so" "$hook"
  done
fi

# Issue 4: Missing Flatpak sandbox override
if [[ "$FLATPAK_OK" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Granting Flatpak Steam permission to access Millennium directory...${NC}"
  execute flatpak override --user --filesystem=/usr/lib/millennium com.valvesoftware.Steam
fi

# Issue 5: Missing or invalid Sudoers drop-in
if [[ "$SUDOERS_OK" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Sudoers drop-in configuration is missing or unauthorized.${NC}"
  echo -e "You must re-run the installer to set up the secure drop-in rules:"
  echo -e "  ${YELLOW}sudo ./install.sh${NC} (from your cloned repository)"
fi

# Issue 6: Ensure daily update timer / cron job is configured and up to date.
# Prefer Go dispatcher when present (native enable clears the other systemd scope).
# Run as current euid so system-scope cleanup works under sudo (no runuser drop).
sched_path=""
mill_go="$(command -v millennium 2>/dev/null || true)"
if [[ -n "$mill_go" ]]; then
  sched_path="$mill_go"
  sched_args=(schedule enable "$UPDATE_CHANNEL")
else
  sched_path=$(resolve_helper_path "millennium-schedule")
  sched_args=(enable "$UPDATE_CHANNEL")
fi
if [[ -n "$sched_path" ]]; then
  if [[ "$SYSTEMD_BOOTED" == "true" ]]; then
    echo -e "\n${YELLOW}[DOCTOR] Refreshing daily systemd update timer (clears conflicting scopes)...${NC}"
    execute "$sched_path" "${sched_args[@]}" || true
  else
    echo -e "\n${YELLOW}[DOCTOR] Refreshing daily cron update job...${NC}"
    if [[ -n "$mill_go" ]]; then
      execute "$mill_go" schedule enable "$UPDATE_CHANNEL" --cron || true
    else
      execute "$sched_path" enable "$UPDATE_CHANNEL" --cron || true
    fi
  fi
else
  echo -e "\n${YELLOW}[DOCTOR] Skip refreshing daily scheduler (millennium / millennium-schedule not found)${NC}"
fi

# Issue 7: Disabled systemd user lingering (Only on systemd booted; skip for system timers)
if [[ "$SYSTEMD_BOOTED" == "true" && "$LINGER_OK" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Enabling systemd user lingering to run updates in the background...${NC}"
  execute loginctl enable-linger "${RUNNING_USER}"
fi

# Issue 8: Incorrect directory permissions or ownership
if [[ "$PERMISSIONS_OK" == false ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Repairing directory permissions and ownership...${NC}"
  for dir in ${unwritable_dirs[@]+"${unwritable_dirs[@]}"}; do
    [[ -n "$dir" ]] || continue
    echo "Correcting ownership and permissions for: ${dir}"
    if [[ "$(id -u)" -eq 0 ]]; then
      execute chown -R "${RUNNING_USER}:${RUNNING_USER}" "$dir"
      execute chmod -R u+rwX "$dir"
    else
      echo -e "${RED}Error: Root privileges are required to fix ownership of ${dir}.${NC}" >&2
      echo -e "Please re-run the doctor with sudo: ${YELLOW}sudo millennium-diag doctor${NC}" >&2
    fi
  done
fi

# Issue 9: Missing skins directories
if [[ "${#missing_skins_dirs[@]}" -gt 0 ]]; then
  echo -e "\n${YELLOW}[DOCTOR] Creating missing skins directories...${NC}"
  for dir in "${missing_skins_dirs[@]}"; do
    echo "Creating directory: ${dir}"
    if [[ "$DRY_RUN" == "false" ]]; then
      execute mkdir -p "$dir"
      if [[ "$(id -u)" -eq 0 ]]; then
        execute chown "${RUNNING_USER}:${RUNNING_USER}" "$dir"
      fi
      execute chmod 755 "$dir"
    fi
  done
fi

}
