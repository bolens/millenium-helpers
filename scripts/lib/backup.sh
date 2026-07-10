# shellcheck shell=bash
# Config, backups and rollback management helpers for Millennium Helpers.
# Sourced by common.sh

load_user_config() {
  local user_name="${SUDO_USER:-$(id -un)}"
  local user_home
  user_home="$(get_user_home "$user_name")"
  if [[ -z "$user_home" ]]; then
    user_home="$HOME"
  fi
  
  local config_dir="${XDG_CONFIG_HOME:-$user_home/.config}/millennium-helpers"
  local config_file="${config_dir}/config.json"
  
  if [[ -f "$config_file" ]]; then
    local parsed
    parsed=$(python3 -c "
import json, sys
try:
    with open('$config_file') as f:
        d = json.load(f)
        print(f\"{d.get('github_token', '')}:{d.get('update_channel', '')}:{d.get('backup_limit', 5)}:{d.get('backup_max_age_days', '')}\")
except Exception:
    print(':::')
" 2>/dev/null || echo ":::")
    
    local config_token="${parsed%%:*}"
    local rest1="${parsed#*:}"
    local config_channel="${rest1%%:*}"
    local rest2="${rest1#*:}"
    local config_limit="${rest2%%:*}"
    local config_max_age="${rest2#*:}"
    
    if [[ -n "$config_token" && -z "${GITHUB_TOKEN:-}" ]]; then
      export GITHUB_TOKEN="$config_token"
    fi
    if [[ -n "$config_channel" && -z "${CONFIG_UPDATE_CHANNEL:-}" ]]; then
      export CONFIG_UPDATE_CHANNEL="$config_channel"
    fi
    if [[ -n "$config_limit" && -z "${CONFIG_BACKUP_LIMIT:-}" ]]; then
      export CONFIG_BACKUP_LIMIT="$config_limit"
    fi
    if [[ -n "$config_max_age" && -z "${CONFIG_BACKUP_MAX_AGE_DAYS:-}" ]]; then
      export CONFIG_BACKUP_MAX_AGE_DAYS="$config_max_age"
    fi
    export CONFIG_BACKUP_LIMIT="${CONFIG_BACKUP_LIMIT:-5}"
    export CONFIG_BACKUP_MAX_AGE_DAYS="${CONFIG_BACKUP_MAX_AGE_DAYS:-}"
  else
    export CONFIG_BACKUP_LIMIT="${CONFIG_BACKUP_LIMIT:-5}"
    export CONFIG_BACKUP_MAX_AGE_DAYS="${CONFIG_BACKUP_MAX_AGE_DAYS:-}"
  fi
}

# Execute configuration loading on source
load_user_config

prune_backups() {
  local max_keep="${1:-${CONFIG_BACKUP_LIMIT:-5}}"
  local age_days="${2:-${CONFIG_BACKUP_MAX_AGE_DAYS:-}}"
  local lib_dir="${MOCK_LIB_DIR:-/usr/lib}"

  local backups=()
  for d in "${lib_dir}"/millennium.bak_*; do
    if [[ -d "$d" ]]; then
      backups+=("$d")
    fi
  done

  if [[ -d "${lib_dir}/millennium.bak" ]]; then
    backups+=("${lib_dir}/millennium.bak")
  fi

  if [[ ${#backups[@]} -eq 0 ]]; then
    return 0
  fi

  local sorted_backups=()
  mapfile -t sorted_backups < <(printf '%s\n' "${backups[@]}" | sort)
  local count=${#sorted_backups[@]}

  # 1. Prune by age if specified
  if [[ -n "$age_days" && "$age_days" =~ ^[0-9]+$ ]]; then
    local now_sec
    now_sec=$(date +%s)
    local limit_sec=$((now_sec - age_days * 86400))

    for b in "${sorted_backups[@]}"; do
      local mtime
      if mtime=$(stat -c %Y "$b" 2>/dev/null); then
        if [[ "$mtime" -lt "$limit_sec" ]]; then
          if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}[DRY RUN] Would delete old backup: ${b}${NC}"
          else
            execute rm -rf "$b"
            echo -e "Removed old backup: $(basename "$b")"
          fi
          local temp_sorted=()
          for item in "${sorted_backups[@]}"; do
            [[ "$item" != "$b" ]] && temp_sorted+=("$item")
          done
          sorted_backups=("${temp_sorted[@]}")
        fi
      fi
    done
    count=${#sorted_backups[@]}
  fi

  # 2. Prune by count
  if [[ "$count" -gt "$max_keep" ]]; then
    local prune_count=$((count - max_keep))
    echo -e "${BLUE}Pruning oldest backups (keeping max ${max_keep})...${NC}"
    for ((i=0; i<prune_count; i++)); do
      local b="${sorted_backups[i]}"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Would prune backup: ${b}${NC}"
      else
        execute rm -rf "$b"
        echo -e "Pruned backup: $(basename "$b")"
      fi
    done
  fi
}

list_backups() {
  local lib_dir="${MOCK_LIB_DIR:-/usr/lib}"
  local backups=()
  for d in "${lib_dir}"/millennium.bak_*; do
    if [[ -d "$d" ]]; then
      backups+=("$(basename "$d")")
    fi
  done
  if [[ -d "${lib_dir}/millennium.bak" ]]; then
    backups+=("millennium.bak")
  fi
  if [[ ${#backups[@]} -gt 0 ]]; then
    printf '%s\n' "${backups[@]}" | sort || true
  fi
}

perform_rollback() {
  local target="${1:-}"
  local lib_dir="${MOCK_LIB_DIR:-/usr/lib}"
  local backups=()
  mapfile -t backups < <(list_backups)
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No backups available to roll back to.${NC}" >&2
    exit 1
  fi
  
  if [[ -z "$target" ]]; then
    if [[ ${#backups[@]} -eq 1 ]]; then
      target="${backups[0]}"
    else
      if [[ ! -t 0 ]]; then
        target="${backups[-1]}"
      else
        echo -e "\n${BLUE}Available Backups:${NC}"
        for i in "${!backups[@]}"; do
          local label="${backups[i]#millennium.bak_}"
          [[ "$label" == "millennium.bak" ]] && label="Legacy Backup (millennium.bak)"
          echo -e "  $((i+1))) ${label}"
        done
        local sel=""
        while true; do
          read -rp "Select a backup to roll back to [1-${#backups[@]}]: " sel
          if [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le ${#backups[@]} ]]; then
            target="${backups[sel-1]}"
            break
          else
            echo -e "${RED}Invalid selection.${NC}"
          fi
        done
      fi
    fi
  elif [[ "$target" == "list" ]]; then
    echo -e "${BLUE}Available Backups:${NC}"
    for b in "${backups[@]}"; do
      local label="${b#millennium.bak_}"
      [[ "$label" == "millennium.bak" ]] && label="Legacy Backup (millennium.bak)"
      echo "  - ${label}"
    done
    exit 0
  else
    local found=""
    for b in "${backups[@]}"; do
      if [[ "$b" == "millennium.bak_${target}" || "$b" == "$target" ]]; then
        found="$b"
        break
      fi
    done
    if [[ -z "$found" ]]; then
      echo -e "${RED}Error: Backup '${target}' not found.${NC}" >&2
      exit 1
    fi
    target="$found"
  fi
  
  local backup_path="${lib_dir}/${target}"
  local dest_dir="${lib_dir}/millennium"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would swap active version with backup ${backup_path}${NC}"
  else
    local rollback_temp
    rollback_temp="${lib_dir}/millennium.rolled_back_$(date +%Y%m%d%H%M%S)"
    if [[ -d "$dest_dir" ]]; then
      execute mv "$dest_dir" "$rollback_temp"
    fi
    if execute mv "$backup_path" "$dest_dir"; then
      echo -e "${GREEN}Rollback successful! Backup ${target#millennium.bak_} is now active.${NC}"
      if [[ -d "$rollback_temp" ]]; then
        local old_ver="unknown"
        if [[ -f "$rollback_temp/version.txt" ]]; then
          old_ver=$(cat "$rollback_temp/version.txt" | tr -d '[:space:]')
        fi
        local moved_bak="${lib_dir}/millennium.bak_${old_ver}"
        execute rm -rf "$moved_bak"
        execute mv "$rollback_temp" "$moved_bak"
        echo -e "Saved rolled back version to $(basename "$moved_bak")"
      fi
    else
      echo -e "${RED}Error: Failed to swap backup.${NC}" >&2
      if [[ -d "$rollback_temp" ]]; then
        execute mv "$rollback_temp" "$dest_dir"
      fi
      exit 1
    fi
  fi
}
