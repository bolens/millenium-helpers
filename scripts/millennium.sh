#!/usr/bin/env bash
# Thin dispatcher for Millennium Helpers: millennium <command> [args...]
set -euo pipefail

show_help() {
  cat << EOF
Usage: $(basename "$0") <command> [args...]

Commands:
  diag       Run diagnostics (millennium-diag)
  doctor     Alias for: diag doctor
  upgrade    Upgrade / install Millennium (millennium-upgrade)
  schedule   Manage auto-update scheduler (millennium-schedule)
  theme      Manage skins/themes (millennium-theme)
  repair     Repair hooks and ownership (millennium-repair)
  purge      Uninstall Millennium (millennium-purge)
  mcp        Run / register the MCP server (millennium-mcp)
  help       Show this help

Examples:
  millennium diag
  millennium doctor
  millennium upgrade --channel beta
  millennium schedule status
  millennium theme list
EOF
}

# Suggest the closest known command for typos (prefix / substring / shared prefix).
suggest_command() {
  local input="$1"
  local -a cmds=(diag doctor upgrade schedule theme repair purge mcp help)
  local c best="" best_score=0
  local score
  for c in "${cmds[@]}"; do
    score=0
    if [[ "$c" == "$input" ]]; then
      echo "$c"
      return 0
    fi
    if [[ "$c" == "$input"* || "$input" == "$c"* ]]; then
      score=3
    elif [[ "$c" == *"$input"* || "$input" == *"$c"* ]]; then
      score=2
    else
      # Shared leading characters
      local i=0
      while [[ $i -lt ${#c} && $i -lt ${#input} && "${c:$i:1}" == "${input:$i:1}" ]]; do
        i=$((i + 1))
      done
      score=$i
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

cmd="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

# Natural alias: millennium doctor → millennium-diag doctor
if [[ "$cmd" == "doctor" ]]; then
  set -- doctor "$@"
  cmd="diag"
fi

case "$cmd" in
  help|-h|--help)
    show_help
    exit 0
    ;;
  -V|--version)
    if command -v millennium-diag &>/dev/null; then
      exec millennium-diag --version
    fi
    echo "millennium (dispatcher)"
    exit 0
    ;;
  diag|upgrade|schedule|theme|repair|purge|mcp)
    target="millennium-${cmd}"
    if ! command -v "$target" &>/dev/null; then
      # Prefer sibling script in the same install/checkout directory
      script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      if [[ -x "${script_dir}/${target}" ]]; then
        exec "${script_dir}/${target}" "$@"
      elif [[ -f "${script_dir}/${target}.sh" ]]; then
        exec bash "${script_dir}/${target}.sh" "$@"
      elif [[ -f "${script_dir}/${target}.py" ]]; then
        exec python3 "${script_dir}/${target}.py" "$@"
      fi
      echo "Error: '${target}' not found on PATH." >&2
      exit 1
    fi
    exec "$target" "$@"
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    suggestion="$(suggest_command "$cmd" || true)"
    if [[ -n "$suggestion" ]]; then
      echo "Did you mean '${suggestion}'?" >&2
    fi
    echo "Run '$(basename "$0") help' for usage." >&2
    exit 1
    ;;
esac
