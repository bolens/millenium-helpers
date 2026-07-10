#!/usr/bin/env bash
# Structural validation for Winget multi-file manifests (beyond YAML parse).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$*" >&2
  echo "error: $*" >&2
  exit 1
}

VERSION="$(tr -d '[:space:]' < VERSION)"
DIR="packaging/winget"
VERSION_FILE="$DIR/bolens.millenniumhelpers.yaml"
INSTALLER_FILE="$DIR/bolens.millenniumhelpers.installer.yaml"
LOCALE_FILE="$DIR/bolens.millenniumhelpers.locale.en-US.yaml"

for f in "$VERSION_FILE" "$INSTALLER_FILE" "$LOCALE_FILE"; do
  [[ -f "$f" ]] || fail "missing $f"
done

python3 - "$VERSION" "$VERSION_FILE" "$INSTALLER_FILE" "$LOCALE_FILE" <<'PY'
import re
import sys
from pathlib import Path

import yaml

expected_version, version_path, installer_path, locale_path = sys.argv[1:5]
errors: list[str] = []

EXPECTED_ALIASES = {
    "millennium-diag",
    "millennium-purge",
    "millennium-repair",
    "millennium-schedule",
    "millennium-theme",
    "millennium-upgrade",
}


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict):
        raise SystemExit(f"error: {path} did not parse to a mapping")
    return data


version = load(version_path)
installer = load(installer_path)
locale = load(locale_path)

expected_id = "bolens.millenniumhelpers"

for path, data in (
    (version_path, version),
    (installer_path, installer),
    (locale_path, locale),
):
    pid = data.get("PackageIdentifier")
    if pid != expected_id:
        errors.append(f"{path}: PackageIdentifier '{pid}' != '{expected_id}'")
    pver = str(data.get("PackageVersion", ""))
    if pver != expected_version:
        errors.append(f"{path}: PackageVersion '{pver}' != VERSION '{expected_version}'")
    if not data.get("ManifestVersion"):
        errors.append(f"{path}: ManifestVersion is missing")

if version.get("ManifestType") != "version":
    errors.append(f"{version_path}: ManifestType must be 'version'")
if installer.get("ManifestType") != "installer":
    errors.append(f"{installer_path}: ManifestType must be 'installer'")
if locale.get("ManifestType") != "defaultLocale":
    errors.append(f"{locale_path}: ManifestType must be 'defaultLocale'")

if installer.get("InstallerType") != "zip":
    errors.append(f"{installer_path}: InstallerType must be 'zip' (multi-command portable)")
if installer.get("NestedInstallerType") != "portable":
    errors.append(f"{installer_path}: NestedInstallerType must be 'portable'")

nested = installer.get("NestedInstallerFiles")
if not isinstance(nested, list) or not nested:
    errors.append(f"{installer_path}: NestedInstallerFiles must be a non-empty list")
else:
    aliases: set[str] = set()
    for item in nested:
        if not isinstance(item, dict):
            errors.append(f"{installer_path}: NestedInstallerFiles entries must be mappings")
            continue
        rel = str(item.get("RelativeFilePath", "")).replace("/", "\\")
        alias = str(item.get("PortableCommandAlias", ""))
        if not rel:
            errors.append(f"{installer_path}: NestedInstallerFiles entry missing RelativeFilePath")
            continue
        if not alias:
            errors.append(f"{installer_path}: NestedInstallerFiles entry missing PortableCommandAlias")
            continue
        aliases.add(alias)
        # Strip GitHub archive root (millenium-helpers-<ref>\...) to verify repo path.
        parts = Path(rel.replace("\\", "/")).parts
        if len(parts) < 2 or not parts[0].startswith("millenium-helpers-"):
            errors.append(
                f"{installer_path}: RelativeFilePath '{rel}' must start with "
                "millenium-helpers-<ref>\\"
            )
            continue
        repo_rel = Path(*parts[1:])
        if not repo_rel.exists():
            errors.append(
                f"{installer_path}: NestedInstallerFiles[{alias}] path "
                f"'{repo_rel}' not found in repo"
            )
        expected_suffix = Path("scripts") / "windows" / f"{alias}.ps1"
        if repo_rel != expected_suffix:
            errors.append(
                f"{installer_path}: NestedInstallerFiles[{alias}] should point at "
                f"{expected_suffix.as_posix()} (got {repo_rel.as_posix()})"
            )
    missing = EXPECTED_ALIASES - aliases
    extra = aliases - EXPECTED_ALIASES
    if missing:
        errors.append(f"{installer_path}: missing PortableCommandAlias entries: {sorted(missing)}")
    if extra:
        errors.append(f"{installer_path}: unexpected PortableCommandAlias entries: {sorted(extra)}")

installers = installer.get("Installers")
if not isinstance(installers, list) or not installers:
    errors.append(f"{installer_path}: Installers must be a non-empty list")
else:
    entry = installers[0]
    url = entry.get("InstallerUrl", "")
    if not isinstance(url, str) or not url.startswith("https://"):
        errors.append(f"{installer_path}: InstallerUrl must be an https URL")
    sha = str(entry.get("InstallerSha256", ""))
    # Unquoted all-zero hashes may parse as int 0 in YAML
    if isinstance(entry.get("InstallerSha256"), int):
        sha = f"{entry['InstallerSha256']:064x}"
    if not re.fullmatch(r"[0-9a-fA-F]{64}", sha):
        errors.append(f"{installer_path}: InstallerSha256 must be 64 hex characters (got {sha!r})")

for field in ("PackageName", "Publisher", "License", "ShortDescription"):
    if not locale.get(field):
        errors.append(f"{locale_path}: missing required field {field}")

if errors:
    for err in errors:
        print(f"::error::{err}", file=sys.stderr)
        print(f"error: {err}", file=sys.stderr)
    raise SystemExit(1)

sha = str(installers[0].get("InstallerSha256", ""))
if set(sha) == {"0"}:
    print("note: InstallerSha256 is still a placeholder (all zeros)")

print("Winget manifest structural checks passed.")
PY
