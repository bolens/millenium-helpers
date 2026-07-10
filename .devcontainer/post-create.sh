#!/usr/bin/env bash
# Runs after the container is created. Keep this non-fatal for the suite so a
# failing test never blocks opening the workspace.
set -euo pipefail

echo "==> Installing PowerShell modules (Pester, PSScriptAnalyzer)..."
pwsh -NoProfile -Command \
  "Install-Module -Name Pester,PSScriptAnalyzer -Force -SkipPublisherCheck -Scope CurrentUser"

if command -v pre-commit >/dev/null 2>&1; then
  echo "==> Installing pre-commit git hooks..."
  pre-commit install
fi

echo "==> Dev container ready."
echo "    Run 'make check-all' to lint and test."
echo "    Run 'make test-all-distros' for multi-distro Docker checks (needs DinD)."
