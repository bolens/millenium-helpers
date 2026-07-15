#!/usr/bin/env zsh
# Nested zsh compsys simulation for Millennium Helpers completions.
# Mocks _arguments to capture (candidate) groups and nested ->args state,
# then invokes _millennium-helpers the same way compsys would.
#
# Usage (from repo root):
#   zsh tests/unit/zsh_completion_sim.zsh
# Prints lines: OK|FAIL <label> and exits non-zero on failure.

emulate -L zsh
setopt err_return no_unset
setopt extended_glob

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZSH_COMP="${REPO_ROOT}/completions/zsh/_millennium-helpers"
ZTMP="$(mktemp -d)"
trap 'rm -rf "$ZTMP"' EXIT

export ZDOTDIR="$ZTMP"
fpath=("${REPO_ROOT}/completions/zsh" $fpath)
autoload -Uz compinit
compinit -u -d "${ZDOTDIR}/.zcompdump" >/dev/null 2>&1 || true

typeset -ga __MH_COMPS
typeset -i __MH_FAILS=0
typeset -i __MH_RUN=0

# Capture completion candidates from _arguments specs like:
#   '1:subcommand:(enable disable status)'
#   {-c,--channel}'[desc]:channel:(stable beta)'
# and from _describe / compadd.
_arguments() {
  local arg
  local -a extracted
  for arg in "$@"; do
    # Named alt lists: '1:command:((${cmds}))' — expand cmds array when present
    if [[ "$arg" == *'(('* ]]; then
      if (( ${+cmds} )); then
        local c
        for c in "${cmds[@]}"; do
          extracted+=("${c%%:*}")
        done
      fi
      continue
    fi
    # Positional lists: '1:label:(a b c)'
    if [[ "$arg" == *\(*\)* ]]; then
      local inner="${arg#*\(}"
      inner="${inner%%\)*}"
      if [[ -n "$inner" && "$inner" != *"*"* ]]; then
        extracted+=(${=inner})
      fi
    fi
    # Flag groups: {-c,--cron}'[desc]'
    if [[ "$arg" == \{*\}* ]]; then
      local flags="${arg#\{}"
      flags="${flags%%\}*}"
      extracted+=(${(s:,:)flags})
    fi
    # Long flags written as '--cron[desc]'
    if [[ "$arg" == --[a-zA-Z]* ]]; then
      local long="${arg%%\[*}"
      extracted+=("$long")
    fi
  done
  __MH_COMPS+=("${extracted[@]}")

  # Nested dispatcher: first _arguments -C with ->args sets state.
  if [[ " $* " == *" -C "* && " $* " == *"->args"* ]]; then
    if (( ${#words} >= 3 )); then
      state=args
      line=("${words[2]}")
    fi
  fi
  return 0
}

_describe() {
  # _describe 'label' arrayname  OR  _describe 'label' -a arrayname
  shift  # descr
  if [[ "$1" == -a || "$1" == -an ]]; then
    local aname="$2"
    eval "__MH_COMPS+=(\"\${${aname}[@]}\")"
  elif [[ "$1" == -* ]]; then
    :
  else
    # values may be passed directly
    __MH_COMPS+=("$@")
  fi
  return 0
}

compadd() {
  local -a vals
  while (( $# )); do
    case "$1" in
      -a|-an)
        shift
        local aname="$1"
        shift
        eval "vals+=(\"\${${aname}[@]}\")"
        ;;
      -d|-X|-J|-V|-x|-P|-S|-p|-s|-W|-q|-Q|-U|-O|-A|-D|-E|-M|-n|-1|-2|-C|-f|-F|-i|-I|-k|-y|-l|-o|-r|-R|-e|-H)
        shift
        (( $# )) && [[ "$1" != -* ]] && shift
        ;;
      --)
        shift
        vals+=("$@")
        break
        ;;
      -*)
        shift
        ;;
      *)
        vals+=("$1")
        shift
        ;;
    esac
  done
  __MH_COMPS+=("${vals[@]}")
  return 0
}

autoload -Uz _millennium-helpers

assert_has() {
  local label="$1"
  local needle="$2"
  (( __MH_RUN++ )) || true
  if (( ${__MH_COMPS[(Ie)$needle]} )); then
    print -r -- "OK $label (has $needle)"
  else
    print -r -- "FAIL $label (missing $needle; got: ${__MH_COMPS[*]})"
    (( __MH_FAILS++ )) || true
  fi
}

run_comp() {
  __MH_COMPS=()
  words=("$@")
  CURRENT=${#words}
  PREFIX="${words[-1]}"
  IPREFIX=""
  ISUFFIX=""
  SUFFIX=""
  service="${words[1]}"
  curcontext=":complete:${service}:"
  context=
  state=
  line=()
  typeset -A opt_args

  # Pre-seed nested state for dispatcher deep completions
  if [[ "$service" == millennium && ${#words} -ge 3 ]]; then
    state=args
    line=("${words[2]}")
  fi

  _millennium-helpers 2>/dev/null || true
}

print -r -- "=== zsh nested completion simulation ==="

# Dispatcher top-level
run_comp millennium ""
assert_has "zsh dispatcher cmds" diag
assert_has "zsh dispatcher cmds" schedule
assert_has "zsh dispatcher cmds" doctor

# Nested: millennium schedule <Tab>
run_comp millennium schedule ""
assert_has "zsh nested schedule actions" enable
assert_has "zsh nested schedule actions" disable
assert_has "zsh nested schedule actions" status
assert_has "zsh nested schedule --cron" --cron
assert_has "zsh nested schedule --quiet" --quiet

# Nested: millennium diag <Tab>
run_comp millennium diag ""
assert_has "zsh nested diag actions" doctor
assert_has "zsh nested diag actions" logs

# Nested: millennium theme <Tab>
run_comp millennium theme ""
assert_has "zsh nested theme actions" list
assert_has "zsh nested theme actions" install

print -r -- "--- zsh_completion_sim: ${__MH_RUN} run, ${__MH_FAILS} failed ---"
(( __MH_FAILS == 0 ))
