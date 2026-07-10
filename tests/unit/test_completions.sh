#!/usr/bin/env bash
# Unit tests for shell completions (static parity + bash/fish runtime smokes).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
COMP_DIR="${REPO_ROOT}/completions"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"

BASH_COMP="${COMP_DIR}/bash/millennium-helpers"
ZSH_COMP="${COMP_DIR}/zsh/_millennium-helpers"
NU_COMP="${COMP_DIR}/nushell/millennium-helpers.nu"
FISH_DIR="${COMP_DIR}/fish"

CLIS=(
  millennium
  millennium-repair
  millennium-upgrade
  millennium-schedule
  millennium-purge
  millennium-diag
  millennium-theme
  millennium-mcp
)

echo -e "${YELLOW}=== Unit tests: shell completions ===${NC}"

# --- Static: no VERSION_PLACEHOLDER anywhere under completions/ ---
placeholder_hits=$(grep -rn '^VERSION_PLACEHOLDER$' "${COMP_DIR}" 2>/dev/null || true)
if [[ -z "$placeholder_hits" ]]; then
  _report true "completions have no bare VERSION_PLACEHOLDER lines"
else
  _report false "completions have no bare VERSION_PLACEHOLDER lines" "$placeholder_hits"
fi

# --- Static: fish has no bare ALL-CAPS placeholder commands (e.g. VERSION_PLACEHOLDER) ---
fish_bad_lines=""
for f in "${FISH_DIR}"/*.fish; do
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" =~ ^# ]] && continue
    # Bare ALL_CAPS identifier is never valid fish (complete/function/end/set/…).
    if [[ "$trimmed" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
      fish_bad_lines+="${f#"$REPO_ROOT"/}: ${trimmed}"$'\n'
    fi
  done < "$f"
done
if [[ -z "$fish_bad_lines" ]]; then
  _report true "fish completions have no bare ALL-CAPS placeholder commands"
else
  _report false "fish completions have no bare ALL-CAPS placeholder commands" "$fish_bad_lines"
fi

# --- Static: inventory across shells ---
bash_text=$(cat "$BASH_COMP")
zsh_text=$(cat "$ZSH_COMP")
nu_text=$(cat "$NU_COMP")
fish_all=$(cat "${FISH_DIR}"/*.fish)

for cli in "${CLIS[@]}"; do
  assert_contains "$bash_text" "$cli" "bash completions mention ${cli}"
  assert_contains "$zsh_text" "$cli" "zsh completions mention ${cli}"
  assert_contains "$nu_text" "$cli" "nushell completions mention ${cli}"
  assert_file_exists "${FISH_DIR}/${cli}.fish" "fish completion file exists for ${cli}"
done

for cli in "${CLIS[@]}"; do
  if grep -qE "complete -F [^ ]+ ${cli}([[:space:]]|$)" "$BASH_COMP"; then
    _report true "bash complete -F registers ${cli}"
  else
    _report false "bash complete -F registers ${cli}"
  fi
done

compdef_line=$(grep -E '^#compdef ' "$ZSH_COMP" | head -1)
for cli in "${CLIS[@]}"; do
  assert_contains "$compdef_line" "$cli" "zsh #compdef lists ${cli}"
done

for cli in "${CLIS[@]}"; do
  if grep -qE "export extern \"${cli}\"" "$NU_COMP"; then
    _report true "nushell export extern \"${cli}\""
  else
    _report false "nushell export extern \"${cli}\""
  fi
done

# --- Static: shared core tokens across bash/zsh/fish/nu ---
# Fish uses `-l dry-run` rather than the literal `--dry-run`, so flag checks
# look for the flag name without requiring a leading `--` in fish files.
assert_token_in_shells() {
  local token="$1"
  local fish_token="${2:-$1}"
  local label="${3:-$token}"
  assert_contains "$bash_text" "$token" "bash completions include ${label}"
  assert_contains "$zsh_text" "$token" "zsh completions include ${label}"
  assert_contains "$fish_all" "$fish_token" "fish completions include ${label}"
  assert_contains "$nu_text" "$token" "nushell completions include ${label}"
}

for cmd in diag doctor upgrade schedule theme repair purge mcp help; do
  assert_token_in_shells "$cmd" "$cmd" "dispatcher cmd '${cmd}'"
done

for action in enable disable status setup config; do
  assert_token_in_shells "$action" "$action" "schedule action '${action}'"
done

assert_token_in_shells "--dry-run" "dry-run" "flag --dry-run"
assert_token_in_shells "--quiet" "quiet" "flag --quiet"
assert_token_in_shells "--cron" "cron" "schedule flag --cron"

assert_token_in_shells "stable" "stable" "channel stable"
assert_token_in_shells "beta" "beta" "channel beta"

assert_token_in_shells "doctor" "doctor" "diag action doctor"
assert_token_in_shells "logs" "logs" "diag action logs"

# --- Bash runtime: drive completer functions ---
bash_runtime_ok=true
bash_runtime_out=$(
  # shellcheck disable=SC1090
  source "$BASH_COMP"

  COMP_WORDS=(millennium "")
  COMP_CWORD=1
  _millennium_dispatcher_comp
  printf 'DISPATCH:%s\n' "${COMPREPLY[*]}"

  COMP_WORDS=(millennium-schedule "")
  COMP_CWORD=1
  _millennium_schedule_comp
  printf 'SCHEDULE:%s\n' "${COMPREPLY[*]}"

  COMP_WORDS=(millennium-schedule enable "")
  COMP_CWORD=2
  _millennium_schedule_comp
  printf 'ENABLE:%s\n' "${COMPREPLY[*]}"

  COMP_WORDS=(millennium-upgrade --channel "")
  COMP_CWORD=2
  _millennium_upgrade_comp
  printf 'CHANNEL:%s\n' "${COMPREPLY[*]}"
) || bash_runtime_ok=false

if [[ "$bash_runtime_ok" == "true" ]]; then
  assert_success 0 "bash completer functions run without error"
else
  assert_success 1 "bash completer functions run without error"
fi

dispatch_line=$(echo "$bash_runtime_out" | grep '^DISPATCH:' | head -1)
schedule_line=$(echo "$bash_runtime_out" | grep '^SCHEDULE:' | head -1)
enable_line=$(echo "$bash_runtime_out" | grep '^ENABLE:' | head -1)
channel_line=$(echo "$bash_runtime_out" | grep '^CHANNEL:' | head -1)

assert_contains "$dispatch_line" "diag" "bash millennium completer offers diag"
assert_contains "$dispatch_line" "schedule" "bash millennium completer offers schedule"
assert_contains "$dispatch_line" "doctor" "bash millennium completer offers doctor"

assert_contains "$schedule_line" "enable" "bash millennium-schedule completer offers enable"
assert_contains "$schedule_line" "status" "bash millennium-schedule completer offers status"
assert_contains "$schedule_line" "setup" "bash millennium-schedule completer offers setup"
assert_contains "$schedule_line" "--cron" "bash millennium-schedule completer offers --cron"

assert_contains "$enable_line" "stable" "bash millennium-schedule enable offers stable"
assert_contains "$enable_line" "beta" "bash millennium-schedule enable offers beta"

assert_contains "$channel_line" "stable" "bash millennium-upgrade --channel offers stable"
assert_contains "$channel_line" "beta" "bash millennium-upgrade --channel offers beta"

# --- Fish runtime: complete -C ---
if command -v fish >/dev/null 2>&1; then
  for f in "${FISH_DIR}"/*.fish; do
    if fish -n "$f" 2>/dev/null; then
      _report true "fish -n ${f#"$REPO_ROOT"/}"
    else
      _report false "fish -n ${f#"$REPO_ROOT"/}"
    fi
  done

  fish_schedule=$(
    fish -c "
      for f in ${FISH_DIR}/*.fish
        source \$f
      end
      complete -C 'millennium-schedule '
    " 2>/dev/null
  ) || true
  assert_contains "$fish_schedule" "enable" "fish complete -C millennium-schedule offers enable"
  assert_contains "$fish_schedule" "status" "fish complete -C millennium-schedule offers status"
  assert_contains "$fish_schedule" "config" "fish complete -C millennium-schedule offers config"

  fish_dispatch=$(
    fish -c "
      for f in ${FISH_DIR}/*.fish
        source \$f
      end
      complete -C 'millennium '
    " 2>/dev/null
  ) || true
  assert_contains "$fish_dispatch" "diag" "fish complete -C millennium offers diag"
  assert_contains "$fish_dispatch" "schedule" "fish complete -C millennium offers schedule"
  assert_contains "$fish_dispatch" "doctor" "fish complete -C millennium offers doctor"

  fish_cron=$(
    fish -c "
      for f in ${FISH_DIR}/*.fish
        source \$f
      end
      complete -C 'millennium-schedule -'
    " 2>/dev/null
  ) || true
  assert_contains "$fish_cron" "cron" "fish complete -C millennium-schedule - offers cron"
else
  echo -e "  ${YELLOW}SKIP:${NC} fish not installed; fish runtime smokes skipped"
fi

# --- Zsh nested compsys simulation ---
if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$ZSH_COMP" 2>/dev/null; then
    _report true "zsh -n _millennium-helpers"
  else
    _report false "zsh -n _millennium-helpers"
  fi
  zsh_sim_rc=0
  zsh_sim_out=$(zsh "${TEST_DIR}/zsh_completion_sim.zsh" 2>&1) || zsh_sim_rc=$?
  zsh_sim_fails=$(echo "$zsh_sim_out" | grep -c '^FAIL ' || true)
  if [[ "$zsh_sim_rc" -eq 0 && "$zsh_sim_fails" -eq 0 ]]; then
    assert_success 0 "zsh nested completion simulation"
  else
    echo "$zsh_sim_out" | grep '^FAIL ' | while IFS= read -r line; do
      echo -e "  ${RED}${line}${NC}" >&2
    done
    assert_success 1 "zsh nested completion simulation"
  fi
else
  echo -e "  ${YELLOW}SKIP:${NC} zsh not installed; zsh nested simulation skipped"
fi

# --- Nushell interactive completions (commandline complete; needs stubs on PATH) ---
if command -v nu >/dev/null 2>&1; then
  if nu -c "source ${NU_COMP}" 2>/dev/null; then
    _report true "nu sources millennium-helpers.nu"
  else
    _report false "nu sources millennium-helpers.nu"
  fi

  NU_BIN=$(mktemp -d)
  for c in millennium millennium-schedule millennium-upgrade millennium-diag \
           millennium-theme millennium-repair millennium-purge millennium-mcp; do
    printf '#!/bin/sh\nexit 0\n' > "${NU_BIN}/${c}"
    chmod +x "${NU_BIN}/${c}"
  done
  nu_out=$(
    PATH="${NU_BIN}:${PATH}" nu -c "
      source ${NU_COMP}
      print 'DISPATCH:'
      print ('millennium ' | commandline complete | str join ' ')
      print 'SCHEDULE:'
      print ('millennium-schedule ' | commandline complete | str join ' ')
      print 'SCHEDULE_EN:'
      print ('millennium-schedule en' | commandline complete | str join ' ')
      print 'SCHEDULE_FLAGS:'
      print ('millennium-schedule -' | commandline complete | str join ' ')
      print 'DIAG:'
      print ('millennium-diag ' | commandline complete | str join ' ')
    " 2>&1
  ) || true
  rm -rf "$NU_BIN"

  dispatch_nu=$(echo "$nu_out" | awk '/^DISPATCH:/{getline; print}')
  schedule_nu=$(echo "$nu_out" | awk '/^SCHEDULE:/{getline; print}')
  schedule_en_nu=$(echo "$nu_out" | awk '/^SCHEDULE_EN:/{getline; print}')
  schedule_flags_nu=$(echo "$nu_out" | awk '/^SCHEDULE_FLAGS:/{getline; print}')
  diag_nu=$(echo "$nu_out" | awk '/^DIAG:/{getline; print}')

  if [[ -z "${dispatch_nu}${schedule_nu}${diag_nu}" ]]; then
    echo -e "  ${YELLOW}SKIP:${NC} nu commandline complete returned no suggestions (need Nushell >= 0.114)"
    while IFS= read -r line || [[ -n "$line" ]]; do
      printf '    %s\n' "$line" >&2
    done <<< "$nu_out"
  else
    assert_contains "$dispatch_nu" "diag" "nu commandline complete millennium offers diag"
    assert_contains "$dispatch_nu" "schedule" "nu commandline complete millennium offers schedule"
    assert_contains "$schedule_nu" "enable" "nu commandline complete millennium-schedule offers enable"
    assert_contains "$schedule_nu" "status" "nu commandline complete millennium-schedule offers status"
    assert_contains "$schedule_en_nu" "enable" "nu commandline complete filters millennium-schedule en"
    assert_contains "$schedule_flags_nu" "--cron" "nu commandline complete offers --cron"
    assert_contains "$diag_nu" "doctor" "nu commandline complete millennium-diag offers doctor"
    assert_contains "$diag_nu" "logs" "nu commandline complete millennium-diag offers logs"
  fi
else
  echo -e "  ${YELLOW}SKIP:${NC} nu not installed; nushell interactive completions skipped"
fi

# --- PowerShell completion script present (runtime covered by Pester on Windows) ---
PS_COMP="${COMP_DIR}/powershell/millennium-helpers.ps1"
assert_file_exists "$PS_COMP" "PowerShell completion script exists"
assert_contains "$(cat "$PS_COMP")" "Register-ArgumentCompleter" \
  "PowerShell completions register argument completers"
assert_contains "$(cat "$PS_COMP")" "Get-MillenniumDispatcherCommands" \
  "PowerShell completions define dispatcher command helper"
assert_contains "$(cat "$PS_COMP")" "Get-MillenniumScheduleActions" \
  "PowerShell completions define schedule action helper"

print_summary
