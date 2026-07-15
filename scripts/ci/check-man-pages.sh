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
# Long-name Bash commands: scripts/millennium-*.sh → matching man/*.1
# PATH millennium is the Go binary (man/millennium.1 required separately).
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
done < <(
  find scripts -maxdepth 1 -type f -name 'millennium-*.sh' -print0 | sort -z
)

if [[ ! -f man/millennium.1 ]]; then
  echo "::error file=man/millennium.1::missing man page for Go PATH dispatcher"
  echo "error: missing man/millennium.1 for Go PATH dispatcher" >&2
  missing=1
else
  echo "OK  bin/millennium → man/millennium.1"
fi

# MCP man page (argv0 twin / thin shim)
if [[ ! -f man/millennium-mcp.1 ]]; then
  echo "::error file=man/millennium-mcp.1::missing man page for millennium-mcp"
  echo "error: missing man/millennium-mcp.1" >&2
  missing=1
else
  echo "OK  millennium-mcp → man/millennium-mcp.1"
fi

# Orphan man pages (no matching script) — warn but do not fail
while IFS= read -r -d '' page; do
  base="$(basename "$page" .1)"
  # PATH millennium is the Go binary (no scripts/millennium.sh).
  if [[ "$base" == "millennium" ]]; then
    continue
  fi
  if [[ ! -f "scripts/${base}.sh" && ! -f "scripts/${base}.py" ]]; then
    echo "::warning file=$page::orphan man page (no scripts/${base}.sh or .py)"
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
