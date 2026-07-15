#!/usr/bin/env bash
# Runtime smoke for shell completions (static parity lives in check-cli-contract).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
COMP_DIR="${REPO_ROOT}/completions"

# shellcheck source=../lib/assertions.sh
source "${TEST_DIR}/../lib/assertions.sh"

BASH_COMP="${COMP_DIR}/bash/millennium-helpers"
ZSH_COMP="${COMP_DIR}/zsh/_millennium-helpers"
NU_COMP="${COMP_DIR}/nushell/millennium-helpers.nu"
FISH_COMP="${COMP_DIR}/fish/millennium.fish"

echo -e "${YELLOW}=== Unit tests: shell completions (runtime) ===${NC}"

assert_file_exists "$BASH_COMP" "bash completion file exists"
assert_file_exists "$ZSH_COMP" "zsh completion file exists"
assert_file_exists "$NU_COMP" "nushell completion file exists"
assert_file_exists "$FISH_COMP" "fish completion file exists"

# --- Bash runtime: drive completer functions ---
bash_runtime_ok=true
bash_runtime_out=$(
  # shellcheck disable=SC1090
  source "$BASH_COMP"

  COMP_WORDS=(millennium "")
  COMP_CWORD=1
  _millennium_dispatcher_comp
  printf 'DISPATCH:%s\n' "${COMPREPLY[*]}"

  COMP_WORDS=(millennium schedule "")
  COMP_CWORD=2
  _millennium_dispatcher_comp
  printf 'SCHEDULE:%s\n' "${COMPREPLY[*]}"

  COMP_WORDS=(millennium schedule enable "")
  COMP_CWORD=3
  _millennium_dispatcher_comp
  printf 'ENABLE:%s\n' "${COMPREPLY[*]}"

  COMP_WORDS=(millennium upgrade --channel "")
  COMP_CWORD=3
  _millennium_dispatcher_comp
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

assert_contains "$schedule_line" "enable" "bash millennium schedule completer offers enable"
assert_contains "$schedule_line" "status" "bash millennium schedule completer offers status"
assert_contains "$schedule_line" "setup" "bash millennium schedule completer offers setup"
assert_contains "$schedule_line" "--cron" "bash millennium schedule completer offers --cron"

assert_contains "$enable_line" "stable" "bash millennium schedule enable offers stable"
assert_contains "$enable_line" "beta" "bash millennium schedule enable offers beta"

assert_contains "$channel_line" "stable" "bash millennium upgrade --channel offers stable"
assert_contains "$channel_line" "beta" "bash millennium upgrade --channel offers beta"
assert_contains "$channel_line" "main" "bash millennium upgrade --channel offers main"

# --- Fish runtime: complete -C ---
if command -v fish >/dev/null 2>&1; then
  if fish -n "$FISH_COMP" 2>/dev/null; then
    _report true "fish -n completions/fish/millennium.fish"
  else
    _report false "fish -n completions/fish/millennium.fish"
  fi

  fish_schedule=$(
    fish -c "
      source ${FISH_COMP}
      complete -C 'millennium schedule '
    " 2>/dev/null
  ) || true
  assert_contains "$fish_schedule" "enable" "fish complete -C millennium schedule offers enable"
  assert_contains "$fish_schedule" "status" "fish complete -C millennium schedule offers status"
  assert_contains "$fish_schedule" "config" "fish complete -C millennium schedule offers config"

  fish_dispatch=$(
    fish -c "
      source ${FISH_COMP}
      complete -C 'millennium '
    " 2>/dev/null
  ) || true
  assert_contains "$fish_dispatch" "diag" "fish complete -C millennium offers diag"
  assert_contains "$fish_dispatch" "schedule" "fish complete -C millennium offers schedule"
  assert_contains "$fish_dispatch" "doctor" "fish complete -C millennium offers doctor"

  fish_cron=$(
    fish -c "
      source ${FISH_COMP}
      complete -C 'millennium schedule -'
    " 2>/dev/null
  ) || true
  assert_contains "$fish_cron" "cron" "fish complete -C millennium schedule - offers cron"
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

# --- Nushell interactive completions ---
if command -v nu >/dev/null 2>&1; then
  if nu -c "source ${NU_COMP}" 2>/dev/null; then
    _report true "nu sources millennium-helpers.nu"
  else
    _report false "nu sources millennium-helpers.nu"
  fi

  NU_BIN=$(mktemp -d)
  printf '#!/bin/sh\nexit 0\n' > "${NU_BIN}/millennium"
  chmod +x "${NU_BIN}/millennium"
  nu_out=$(
    PATH="${NU_BIN}:${PATH}" nu -c "
      source ${NU_COMP}
      print 'DISPATCH:'
      print ('millennium ' | commandline complete | str join ' ')
      print 'SCHEDULE:'
      print ('millennium schedule ' | commandline complete | str join ' ')
      print 'SCHEDULE_EN:'
      print ('millennium schedule en' | commandline complete | str join ' ')
    " 2>/dev/null
  ) || true
  rm -rf "$NU_BIN"
  nu_dispatch=$(echo "$nu_out" | awk '/^DISPATCH:/{getline; print}')
  nu_schedule=$(echo "$nu_out" | awk '/^SCHEDULE:/{getline; print}')
  assert_contains "$nu_dispatch" "schedule" "nu commandline complete offers schedule"
  assert_contains "$nu_schedule" "enable" "nu schedule complete offers enable"
else
  echo -e "  ${YELLOW}SKIP:${NC} nu not installed; nushell runtime smokes skipped"
fi

print_summary
