# shellcheck shell=bash
# Diagnostic UI helpers (status glyphs and print_diag_item)
_diag_use_unicode() {
  # Explicit opt-out only. Default to unicode glyphs for normal terminals;
  # set NO_UNICODE=1 for ASCII OK/WARN/FAIL markers.
  [[ -z "${NO_UNICODE:-}" ]]
}

print_diag_item() {
  local status="$1"
  local label="$2"
  local value="$3"
  local ok_g warn_g err_g

  if _diag_use_unicode; then
    ok_g="✔"
    warn_g="!"
    err_g="✘"
  else
    ok_g="OK"
    warn_g="WARN"
    err_g="FAIL"
  fi

  if [[ "$status" == "ok" ]]; then
    printf "  [${GREEN}%s${NC}] %-45s : %b\n" "$ok_g" "$label" "$value"
  elif [[ "$status" == "warn" ]]; then
    printf "  [${YELLOW}%s${NC}] %-45s : %b\n" "$warn_g" "$label" "$value"
  else
    printf "  [${RED}%s${NC}] %-45s : %b\n" "$err_g" "$label" "$value"
  fi
}
