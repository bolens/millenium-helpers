# shellcheck shell=bash
# Dispatcher helpers for millennium.sh (no common.sh dependency)

# Suggest the closest known command for typos.
# Scoring mirrors suggest_closest in lib/logging.sh: 4=prefix, 3=substring,
# else shared leading chars; subsequence (e.g. lst→list) scores 3−|len gap| (floor 2).
# Emit only when best_score >= 2.
suggest_command() {
  local input="$1"
  local -a cmds=(diag doctor upgrade schedule theme repair purge mcp help)
  local c best="" best_score=0
  local score
  [[ -z "$input" ]] && return 0
  for c in "${cmds[@]}"; do
    score=0
    if [[ "$c" == "$input" ]]; then
      echo "$c"
      return 0
    fi
    if [[ "$c" == "$input"* || "$input" == "$c"* ]]; then
      score=4
    elif [[ "$c" == *"$input"* || "$input" == *"$c"* ]]; then
      score=3
    else
      # Identical leading characters (e.g. "upg" vs "upgrade" → 3).
      local i=0
      while [[ $i -lt ${#c} && $i -lt ${#input} && "${c:$i:1}" == "${input:$i:1}" ]]; do
        i=$((i + 1))
      done
      score=$i
      # Subsequence with gaps; len>=2 avoids matching every command on one letter.
      if [[ ${#input} -ge 2 ]]; then
        local ni=0 hi=0
        while [[ $ni -lt ${#input} && $hi -lt ${#c} ]]; do
          if [[ "${input:$ni:1}" == "${c:$hi:1}" ]]; then
            ni=$((ni + 1))
          fi
          hi=$((hi + 1))
        done
        if [[ $ni -eq ${#input} ]]; then
          local len_diff=$(( ${#c} - ${#input} ))
          [[ $len_diff -lt 0 ]] && len_diff=$(( -len_diff ))
          local sub_score=$((3 - len_diff))
          [[ $sub_score -lt 2 ]] && sub_score=2
          if [[ $sub_score -gt $score ]]; then
            score=$sub_score
          fi
        fi
      fi
    fi
    if [[ $score -gt $best_score ]]; then
      best_score=$score
      best=$c
    fi
  done
  if [[ $best_score -ge 2 && -n "$best" ]]; then
    echo "$best"
  fi
}

# Resolve and exec a millennium-* sibling (PATH, then script_dir wrappers / sources).
# $1 is the short command name (diag, upgrade, …); remaining args are forwarded.
# DISPATCHER_SCRIPT_DIR must be set by the caller to the dispatcher install directory.
exec_dispatcher_command() {
  local cmd="$1"
  shift
  local target="millennium-${cmd}"
  local script_dir="${DISPATCHER_SCRIPT_DIR:-}"

  if command -v "$target" &>/dev/null; then
    exec "$target" "$@"
  fi

  if [[ -z "$script_dir" ]]; then
    echo "Error: '${target}' not found on PATH." >&2
    return 1
  fi

  if [[ -x "${script_dir}/${target}" ]]; then
    exec "${script_dir}/${target}" "$@"
  elif [[ -f "${script_dir}/${target}.sh" ]]; then
    exec bash "${script_dir}/${target}.sh" "$@"
  elif [[ -f "${script_dir}/${target}.py" ]]; then
    exec python3 "${script_dir}/${target}.py" "$@"
  fi

  echo "Error: '${target}' not found on PATH." >&2
  return 1
}
