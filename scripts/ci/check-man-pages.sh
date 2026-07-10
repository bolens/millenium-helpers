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
[[ -d scripts ]] || fail "scripts/ directory is missing"

missing=0
# Bash commands: scripts/millennium-*.sh → man/millennium-*.1
while IFS= read -r -d '' script; do
  base="$(basename "$script" .sh)"
  page="man/${base}.1"
  if [[ ! -f "$page" ]]; then
    echo "::error file=$script::missing man page $page"
    echo "error: missing man page for $script → expected $page" >&2
    missing=1
  else
    echo "OK  $script → $page"
  fi
done < <(find scripts -maxdepth 1 -type f -name 'millennium-*.sh' -print0 | sort -z)

# MCP is a Python entrypoint with its own man page
if [[ -f scripts/millennium-mcp.py ]]; then
  if [[ ! -f man/millennium-mcp.1 ]]; then
    echo "::error file=scripts/millennium-mcp.py::missing man page man/millennium-mcp.1"
    echo "error: missing man page for scripts/millennium-mcp.py" >&2
    missing=1
  else
    echo "OK  scripts/millennium-mcp.py → man/millennium-mcp.1"
  fi
fi

# Orphan man pages (no matching script) — warn but do not fail
while IFS= read -r -d '' page; do
  base="$(basename "$page" .1)"
  if [[ ! -f "scripts/${base}.sh" && ! -f "scripts/${base}.py" ]]; then
    echo "::warning file=$page::orphan man page (no scripts/${base}.sh or .py)"
    echo "warning: orphan man page $page" >&2
  fi
done < <(find man -maxdepth 1 -type f -name '*.1' -print0 | sort -z)

[[ "$missing" -eq 0 ]] || fail "one or more man pages are missing"

if command -v mandoc >/dev/null 2>&1; then
  echo "Running mandoc -T lint on man pages..."
  for page in man/*.1; do
    if ! mandoc -T lint "$page" >/tmp/mandoc-lint.out 2>&1; then
      cat /tmp/mandoc-lint.out >&2
      fail "mandoc lint failed for $page"
    fi
    # Surface warnings without failing the job
    if [[ -s /tmp/mandoc-lint.out ]]; then
      echo "lint notes for $page:"
      cat /tmp/mandoc-lint.out
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
