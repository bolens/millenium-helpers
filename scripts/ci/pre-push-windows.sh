#!/usr/bin/env bash
# pre-push: run Windows Pester when the push range touches Windows sources.
# Skips when pwsh is missing or no relevant diffs vs the upstream merge-base.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v pwsh >/dev/null 2>&1; then
  echo "skip: pwsh not installed (Windows Pester not run)"
  exit 0
fi

base=""
if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
  base="$(git merge-base HEAD '@{upstream}')"
elif git rev-parse --verify origin/main >/dev/null 2>&1; then
  base="$(git merge-base HEAD origin/main)"
elif git rev-parse --verify main >/dev/null 2>&1; then
  base="$(git merge-base HEAD main)"
fi

if [[ -z "$base" ]]; then
  echo "skip: could not resolve upstream merge-base"
  exit 0
fi

if ! git diff --name-only "$base"...HEAD | grep -qE '^(scripts/windows/|tests/windows/|completions/powershell/)'; then
  echo "skip: no Windows-related changes in $base...HEAD"
  exit 0
fi

echo "Windows-related changes detected — running make test-windows..."
make test-windows
