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
if locale.get("ManifestType") != "locale":
    errors.append(f"{locale_path}: ManifestType must be 'locale'")

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
    commands = entry.get("Commands")
    if not isinstance(commands, list) or not commands:
        errors.append(f"{installer_path}: Commands must be a non-empty list")
    aliases = entry.get("PortableCommandAliases")
    if not isinstance(aliases, dict) or not aliases:
        errors.append(
            f"{installer_path}: PortableCommandAliases must be a non-empty mapping"
        )
    else:
        for cmd, script in aliases.items():
            script_path = Path(str(script))
            if not script_path.exists():
                errors.append(
                    f"{installer_path}: PortableCommandAliases[{cmd}] "
                    f"path '{script}' not found in repo"
                )

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
