#!/usr/bin/env bash
# Cross-link checks for project docs (guides, root docs, man pages, licensing).
# Fails when the documentation graph drifts. Prefer: make check-docs
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$*" >&2
  echo "error: $*" >&2
  exit 1
}

need_file() {
  local f="$1"
  [[ -f "$f" ]] || fail "missing required file: $f"
}

need_contains() {
  local f needle msg
  f="$1"
  needle="$2"
  msg="${3:-$f must contain: $needle}"
  [[ -f "$f" ]] || fail "missing file for content check: $f"
  if ! grep -qF -- "$needle" "$f"; then
    fail "$msg"
  fi
}

# ---------------------------------------------------------------------------
# Index + inventory
# ---------------------------------------------------------------------------

need_file "docs/README.md"
need_file "README.md"
need_file "CONTRIBUTING.md"
need_file "SECURITY.md"
need_file "CHANGELOG.md"

need_contains "docs/README.md" "## Guides" \
  "docs/README.md must have a Guides section"
need_contains "docs/README.md" "make check-docs" \
  "docs/README.md must document make check-docs"
need_contains "docs/README.md" "../README.md" \
  "docs/README.md must link to the project README"
need_contains "docs/README.md" "../CONTRIBUTING.md" \
  "docs/README.md must link to CONTRIBUTING.md"
need_contains "docs/README.md" "../SECURITY.md" \
  "docs/README.md must link to SECURITY.md"
need_contains "docs/README.md" "../CHANGELOG.md" \
  "docs/README.md must link to CHANGELOG.md"
need_contains "docs/README.md" "## Related" \
  "docs/README.md must end with a Related section"

need_contains "README.md" "## Further reading" \
  "README.md must have a Further reading section"
need_contains "README.md" "docs/README.md" \
  "README.md Further reading must link to the docs index"

need_contains "CONTRIBUTING.md" "docs/README.md" \
  "CONTRIBUTING.md must link to docs/README.md"
need_contains "CONTRIBUTING.md" "## Documentation" \
  "CONTRIBUTING.md must have a ## Documentation section"

need_contains "SECURITY.md" "docs/README.md" \
  "SECURITY.md must link to docs/README.md"
need_contains "SECURITY.md" "docs/security_troubleshooting.md" \
  "SECURITY.md must link to docs/security_troubleshooting.md"
need_contains "SECURITY.md" "docs/mcp.md" \
  "SECURITY.md must link to docs/mcp.md"

# Every guide under docs/ (except the index) must be listed in the index + README
while IFS= read -r -d '' doc; do
  base="$(basename "$doc")"
  [[ "$base" == "README.md" ]] && continue
  need_contains "docs/README.md" "$base" \
    "docs/README.md Guides table must list $base"
  need_contains "README.md" "docs/${base}" \
    "README.md Further reading must list docs/${base}"
done < <(find docs -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

# Every guide (except index) must have Related + link to the docs index + project README
while IFS= read -r -d '' doc; do
  base="$(basename "$doc")"
  [[ "$base" == "README.md" ]] && continue
  need_contains "$doc" "## Related" \
    "$doc must have a ## Related section"
  need_contains "$doc" "](README.md)" \
    "$doc Related section must link to the docs index (README.md)"
  need_contains "$doc" "../README.md" \
    "$doc must link to the project README (../README.md)"
done < <(find docs -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

# ---------------------------------------------------------------------------
# Topical edges (where docs should point for their subject)
# ---------------------------------------------------------------------------

# mcp.md
need_contains "docs/mcp.md" "security_troubleshooting.md" \
  "docs/mcp.md must link to security_troubleshooting.md"
need_contains "docs/mcp.md" "licensing.md" \
  "docs/mcp.md must link to licensing.md"
need_contains "docs/mcp.md" "uninstall_dryrun.md" \
  "docs/mcp.md must link to uninstall_dryrun.md (purge / undo paths)"

# security_troubleshooting.md
need_contains "docs/security_troubleshooting.md" "mcp.md" \
  "docs/security_troubleshooting.md must link to mcp.md"
need_contains "docs/security_troubleshooting.md" "steam_deck.md" \
  "docs/security_troubleshooting.md must link to steam_deck.md"
need_contains "docs/security_troubleshooting.md" "licensing.md" \
  "docs/security_troubleshooting.md must link to licensing.md"
need_contains "docs/security_troubleshooting.md" "../SECURITY.md" \
  "docs/security_troubleshooting.md must link to SECURITY.md"
need_contains "docs/security_troubleshooting.md" "uninstall_dryrun.md" \
  "docs/security_troubleshooting.md must link to uninstall_dryrun.md"

# steam_deck.md
need_contains "docs/steam_deck.md" "security_troubleshooting.md" \
  "docs/steam_deck.md must link to security_troubleshooting.md"
need_contains "docs/steam_deck.md" "uninstall_dryrun.md" \
  "docs/steam_deck.md must link to uninstall_dryrun.md"
need_contains "docs/steam_deck.md" "licensing.md" \
  "docs/steam_deck.md must link to licensing.md"

# uninstall_dryrun.md
need_contains "docs/uninstall_dryrun.md" "security_troubleshooting.md" \
  "docs/uninstall_dryrun.md must link to security_troubleshooting.md"
need_contains "docs/uninstall_dryrun.md" "steam_deck.md" \
  "docs/uninstall_dryrun.md must link to steam_deck.md"
need_contains "docs/uninstall_dryrun.md" "licensing.md" \
  "docs/uninstall_dryrun.md must link to licensing.md"

# release_runbook.md
need_contains "docs/release_runbook.md" "../CONTRIBUTING.md" \
  "docs/release_runbook.md must link to CONTRIBUTING.md"
need_contains "docs/release_runbook.md" "licensing.md" \
  "docs/release_runbook.md must link to licensing.md"
need_contains "docs/release_runbook.md" "README.md" \
  "docs/release_runbook.md must link to the docs index"

# licensing.md hub edges to sibling guides
need_contains "docs/licensing.md" "mcp.md" \
  "docs/licensing.md must link to mcp.md"
need_contains "docs/licensing.md" "security_troubleshooting.md" \
  "docs/licensing.md must link to security_troubleshooting.md"
need_contains "docs/licensing.md" "steam_deck.md" \
  "docs/licensing.md must link to steam_deck.md"
need_contains "docs/licensing.md" "uninstall_dryrun.md" \
  "docs/licensing.md must link to uninstall_dryrun.md"
need_contains "docs/licensing.md" "release_runbook.md" \
  "docs/licensing.md must link to release_runbook.md"
need_contains "docs/licensing.md" "unification-audit.md" \
  "docs/licensing.md must link to unification-audit.md"
need_contains "docs/licensing.md" "unification-roadmap.md" \
  "docs/licensing.md must link to unification-roadmap.md"
need_contains "docs/licensing.md" "](README.md)" \
  "docs/licensing.md must link to the docs index"

# unification guides
need_contains "docs/unification-audit.md" "unification-roadmap.md" \
  "docs/unification-audit.md must link to unification-roadmap.md"
need_contains "docs/unification-roadmap.md" "unification-audit.md" \
  "docs/unification-roadmap.md must link to unification-audit.md"
need_contains "docs/unification-roadmap.md" "../spec/cli-contract.yaml" \
  "docs/unification-roadmap.md must link to the CLI contract"

# ---------------------------------------------------------------------------
# Man pages → matching guides
# ---------------------------------------------------------------------------

need_contains "man/millennium.1" "docs/README.md" \
  "man/millennium.1 must reference the docs index"
need_contains "man/millennium-mcp.1" "docs/mcp.md" \
  "man/millennium-mcp.1 must reference docs/mcp.md"
need_contains "man/millennium-diag.1" "docs/steam_deck.md" \
  "man/millennium-diag.1 must reference docs/steam_deck.md"
need_contains "man/millennium-diag.1" "docs/security_troubleshooting.md" \
  "man/millennium-diag.1 must reference docs/security_troubleshooting.md"
need_contains "man/millennium-upgrade.1" "docs/licensing.md" \
  "man/millennium-upgrade.1 must reference docs/licensing.md"
need_contains "man/millennium-purge.1" "docs/uninstall_dryrun.md" \
  "man/millennium-purge.1 must reference docs/uninstall_dryrun.md"
need_contains "man/millennium-repair.1" "docs/security_troubleshooting.md" \
  "man/millennium-repair.1 must reference docs/security_troubleshooting.md"
need_contains "man/millennium-schedule.1" "docs/security_troubleshooting.md" \
  "man/millennium-schedule.1 must reference docs/security_troubleshooting.md"
need_contains "man/millennium-theme.1" "docs/README.md" \
  "man/millennium-theme.1 must reference the docs index"

# ---------------------------------------------------------------------------
# Licensing attribution (helpers + Millennium client)
# ---------------------------------------------------------------------------

need_file "LICENSE"
need_file "docs/licensing.md"
need_file "third_party/MILLENNIUM-LICENSE.md"
need_file "third_party/README.md"
need_file "go/internal/upgrade/install.go"

need_contains "third_party/MILLENNIUM-LICENSE.md" "MIT License" \
  "third_party/MILLENNIUM-LICENSE.md must be an MIT license text"
need_contains "third_party/MILLENNIUM-LICENSE.md" "Project Millennium" \
  "third_party/MILLENNIUM-LICENSE.md must attribute Project Millennium"

UPSTREAM_LICENSE_URL="https://github.com/SteamClientHomebrew/Millennium/blob/main/LICENSE.md"
UPSTREAM_RAW_HINT="SteamClientHomebrew/Millennium"

need_contains "docs/licensing.md" "](../LICENSE)" \
  "docs/licensing.md must link to ../LICENSE"
need_contains "docs/licensing.md" "third_party/MILLENNIUM-LICENSE.md" \
  "docs/licensing.md must link to the vendored Millennium license"
need_contains "docs/licensing.md" "$UPSTREAM_LICENSE_URL" \
  "docs/licensing.md must link to upstream Millennium LICENSE.md"
need_contains "docs/licensing.md" "README.md#license" \
  "docs/licensing.md must link to README § License"
need_contains "docs/licensing.md" "millennium-upgrade" \
  "docs/licensing.md must mention millennium-upgrade install behavior"
need_contains "docs/licensing.md" "make check-docs" \
  "docs/licensing.md must document make check-docs"
need_contains "docs/licensing.md" "third_party/README.md" \
  "docs/licensing.md must link to third_party/README.md"
need_contains "docs/licensing.md" "CONTRIBUTING.md#licensing" \
  "docs/licensing.md must link to CONTRIBUTING § Licensing"

need_contains "third_party/README.md" "docs/licensing.md" \
  "third_party/README.md must link to docs/licensing.md"
need_contains "third_party/README.md" "../LICENSE" \
  "third_party/README.md must distinguish helpers LICENSE"
need_contains "third_party/README.md" "$UPSTREAM_LICENSE_URL" \
  "third_party/README.md must link to upstream LICENSE.md"
need_contains "third_party/README.md" "README.md#license" \
  "third_party/README.md must link to README § License"
need_contains "third_party/README.md" "docs/README.md" \
  "third_party/README.md must link to the docs index"

need_contains "README.md" "docs/licensing.md" \
  "README.md must link to docs/licensing.md"
need_contains "README.md" "](LICENSE)" \
  "README.md must link to LICENSE"
need_contains "README.md" "third_party/MILLENNIUM-LICENSE.md" \
  "README.md must link to third_party/MILLENNIUM-LICENSE.md"
need_contains "README.md" "$UPSTREAM_LICENSE_URL" \
  "README.md must link to upstream Millennium LICENSE.md"
need_contains "README.md" "not affiliated" \
  "README.md License section must include a non-affiliation disclaimer"

need_contains "CONTRIBUTING.md" "docs/licensing.md" \
  "CONTRIBUTING.md must link to docs/licensing.md"
need_contains "CONTRIBUTING.md" "## Licensing" \
  "CONTRIBUTING.md must have a ## Licensing section"
need_contains "SECURITY.md" "docs/licensing.md" \
  "SECURITY.md must link to docs/licensing.md"

while IFS= read -r -d '' page; do
  need_contains "$page" ".SH LICENSE" \
    "$page must include a .SH LICENSE section"
  need_contains "$page" "docs/licensing.md" \
    "$page LICENSE section must reference docs/licensing.md"
done < <(find man -maxdepth 1 -type f -name '*.1' -print0 | sort -z)

need_contains "man/millennium.1" "$UPSTREAM_LICENSE_URL" \
  "man/millennium.1 must link to upstream Millennium LICENSE.md"
need_contains "man/millennium-upgrade.1" "$UPSTREAM_LICENSE_URL" \
  "man/millennium-upgrade.1 must link to upstream Millennium LICENSE.md"
need_contains "man/millennium-upgrade.1" "MILLENNIUM\\-LICENSE" \
  "man/millennium-upgrade.1 must mention the vendored MILLENNIUM-LICENSE"

need_contains "packaging/winget/bolens.millenniumhelpers.locale.en-US.yaml" \
  "$UPSTREAM_RAW_HINT" \
  "winget locale must attribute SteamClientHomebrew/Millennium"
need_contains "packaging/winget-git/bolens.millenniumhelpers.git.locale.en-US.yaml" \
  "Project Millennium" \
  "winget-git locale must mention Project Millennium"

need_contains ".github/workflows/release.yml" "third_party/MILLENNIUM-LICENSE.md" \
  "release.yml must package third_party/MILLENNIUM-LICENSE.md"

need_contains "go/internal/upgrade/install.go" "docs/licensing.md" \
  "go/internal/upgrade/install.go must reference docs/licensing.md"
need_contains "docs/licensing.md" "go/internal/upgrade" \
  "docs/licensing.md must mention Go upgrade license install"

echo "Documentation cross-links OK."
