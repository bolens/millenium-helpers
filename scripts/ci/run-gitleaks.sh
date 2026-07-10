#!/usr/bin/env bash
# Scan staged changes for secrets. Skips cleanly when gitleaks is not installed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "skip: gitleaks not installed (pre-commit-hooks detect-private-key still runs; see CONTRIBUTING.md)"
  exit 0
fi

# protect --staged scans the index (what would be committed)
gitleaks protect --staged --verbose --redact
