#!/usr/bin/env bash
# Ensure every user-facing command has a matching man page, and that pages parse.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$*" >&2
  echo "error: $*" >&2
  exit 1
}

[[ -d man ]] || fail "man/ directory is missing"

missing=0
# man/millennium.1 plus per-command pages (basename millennium-<cmd>.1).
# PATH ships only `millennium`; long-name pages document `millennium <cmd>`.
REQUIRED_MAN=(
  millennium
  millennium-mcp
  millennium-repair
  millennium-upgrade
  millennium-schedule
  millennium-purge
  millennium-diag
  millennium-theme
)

for base in "${REQUIRED_MAN[@]}"; do
  page="man/${base}.1"
  if [[ ! -f "$page" ]]; then
    echo "::error file=$page::missing man page for $base"
    echo "error: missing man page for $base → expected $page" >&2
    missing=1
  else
    echo "OK  $base → $page"
  fi
done

# Unexpected man pages (not in the required set) — warn but do not fail.
is_required_man() {
  local cand="$1" r
  for r in "${REQUIRED_MAN[@]}"; do
    [[ "$r" == "$cand" ]] && return 0
  done
  return 1
}
while IFS= read -r -d '' page; do
  base="$(basename "$page" .1)"
  if ! is_required_man "$base"; then
    echo "::warning file=$page::orphan man page (not a Go PATH command)"
    echo "warning: orphan man page $page" >&2
  fi
done < <(find man -maxdepth 1 -type f -name '*.1' -print0 | sort -z)

[[ "$missing" -eq 0 ]] || fail "one or more man pages are missing"

if command -v mandoc >/dev/null 2>&1; then
  echo "Running mandoc -T lint on man pages..."
  for page in man/*.1; do
    # mandoc returns non-zero for warnings as well as errors. Treat ERROR/
    # FATAL as failures; surface WARNING/STYLE as notes without failing CI.
    set +e
    mandoc -T lint "$page" >/tmp/mandoc-lint.out 2>&1
    mandoc_rc=$?
    set -e
    if [[ -s /tmp/mandoc-lint.out ]]; then
      if grep -Eq '[[:space:]](ERROR|FATAL):' /tmp/mandoc-lint.out; then
        cat /tmp/mandoc-lint.out >&2
        fail "mandoc lint failed for $page"
      fi
      echo "lint notes for $page:"
      cat /tmp/mandoc-lint.out
    elif [[ "$mandoc_rc" -ne 0 ]]; then
      fail "mandoc lint failed for $page (exit $mandoc_rc, no diagnostics)"
    else
      echo "lint OK  $page"
    fi
  done
elif command -v man >/dev/null 2>&1; then
  echo "mandoc not found; verifying man can format pages..."
  for page in man/*.1; do
    man -l "$page" >/dev/null || fail "man -l failed for $page"
    echo "format OK  $page"
  done
else
  echo "Neither mandoc nor man available; checking required macros..."
  for page in man/*.1; do
    grep -q '^\.TH ' "$page" || fail "$page missing .TH header"
    grep -q '^\.SH NAME' "$page" || fail "$page missing .SH NAME"
    echo "header OK  $page"
  done
fi

echo "Man page coverage check passed."
