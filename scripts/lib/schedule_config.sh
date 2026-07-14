# shellcheck shell=bash
# Schedule helpers for millennium-schedule.sh (schedule_config.sh)

manage_config() {
  local action="${CONFIG_ACTION:-list}"
  local key="${CONFIG_KEY:-}"
  local val="${CONFIG_VALUE:-}"

  local user_name="${SUDO_USER:-$(id -un)}"
  local user_home
  user_home="$(get_user_home "$user_name")"
  if [[ -z "$user_home" ]]; then
    user_home="$HOME"
  fi
  local config_dir="${XDG_CONFIG_HOME:-$user_home/.config}/millennium-helpers"
  local config_file="${config_dir}/config.json"

  case "$action" in
    list|show)
      python3 -c "
import json, os
config_file = '$config_file'
data = {}
if os.path.exists(config_file):
    try:
        with open(config_file) as f:
            data = json.load(f)
    except Exception:
        pass

keys = ['update_channel', 'github_token', 'backup_limit', 'backup_max_age_days']
print('=== Millennium Helpers Configuration ===')
for k in keys:
    val = data.get(k, None)
    if k == 'github_token' and val:
        val_str = val[:4] + '*' * 8 if len(val) >= 4 else '*' * 8
    elif val is None:
        val_str = '(not set)'
        if k == 'update_channel':
            val_str = 'stable (default)'
        elif k == 'backup_limit':
            val_str = '5 (default)'
    else:
        val_str = str(val)
    print(f'  {k:<20} : {val_str}')
" || echo "Failed to read configuration."
      ;;
    get)
      if [[ -z "$key" ]]; then
        echo -e "${RED}Error: config get requires a key name.${NC}" >&2
        exit 1
      fi
      if [[ "$key" != "update_channel" && "$key" != "github_token" && "$key" != "backup_limit" && "$key" != "backup_max_age_days" ]]; then
        echo -e "${RED}Error: Invalid config key '${key}'. Valid keys: update_channel, github_token, backup_limit, backup_max_age_days${NC}" >&2
        exit 1
      fi
      python3 -c "
import json, os, sys
config_file = '$config_file'
if os.path.exists(config_file):
    try:
        with open(config_file) as f:
            data = json.load(f)
            val = data.get('$key', None)
            if val is not None:
                print(val)
                sys.exit(0)
    except Exception:
        pass
print('')
" 2>/dev/null
      ;;
    set)
      if [[ -z "$key" ]]; then
        echo -e "${RED}Error: config set requires a key name.${NC}" >&2
        exit 1
      fi
      if [[ "$key" != "update_channel" && "$key" != "github_token" && "$key" != "backup_limit" && "$key" != "backup_max_age_days" ]]; then
        echo -e "${RED}Error: Invalid config key '${key}'. Valid keys: update_channel, github_token, backup_limit, backup_max_age_days${NC}" >&2
        exit 1
      fi
      if [[ "$key" == "update_channel" ]]; then
        if [[ "$val" != "stable" && "$val" != "beta" && "$val" != "main" ]]; then
          echo -e "${RED}Error: update_channel must be 'stable', 'beta', or 'main'.${NC}" >&2
          exit 1
        fi
      elif [[ "$key" == "backup_limit" ]]; then
        if [[ ! "$val" =~ ^[0-9]+$ || "$val" -lt 1 ]]; then
          echo -e "${RED}Error: backup_limit must be a positive integer >= 1.${NC}" >&2
          exit 1
        fi
      elif [[ "$key" == "backup_max_age_days" ]]; then
        if [[ -n "$val" && ! "$val" =~ ^[0-9]+$ ]]; then
          echo -e "${RED}Error: backup_max_age_days must be a positive integer or empty.${NC}" >&2
          exit 1
        fi
      fi

      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Would set config option ${key} to ${val}${NC}"
      else
        execute mkdir -p "$config_dir"
        execute chmod 700 "$config_dir"
        python3 -c "
import json, os
config_file = '$config_file'
data = {}
if os.path.exists(config_file):
    try:
        with open(config_file) as f:
            data = json.load(f)
    except Exception:
        pass

val_raw = '$val'
if '$key' in ['backup_limit', 'backup_max_age_days']:
    if val_raw == '':
        data['$key'] = None
    else:
        data['$key'] = int(val_raw)
else:
    data['$key'] = val_raw

with open(config_file, 'w') as f:
    json.dump(data, f, indent=2)
" && echo -e "${GREEN}Config option ${key} set to '${val}' successfully.${NC}"

        if [[ -f "$config_file" ]]; then
          execute chmod 600 "$config_file"
          if [[ "$(id -u)" -eq 0 && "$user_name" != "root" ]]; then
            execute chown -R "${user_name}:${user_name}" "$config_dir"
          fi
        fi
      fi
      ;;
    *)
      echo -e "${RED}Error: Unknown config action '${action}'. Use get, set, or list.${NC}" >&2
      exit 1
      ;;
  esac
}
