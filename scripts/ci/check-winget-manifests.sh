#!/usr/bin/env bash
# Structural validation for Winget multi-file manifests (beyond YAML parse).
# WinGet portable NestedInstallerFiles only allow .exe, so this package cannot
# pass `winget validate` as a multi-script PowerShell portable. We still check
# YAML structure and version sync here; CI skips `winget validate`.
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
if locale.get("ManifestType") != "defaultLocale":
    errors.append(f"{locale_path}: ManifestType must be 'defaultLocale'")

# PowerShell helpers cannot use NestedInstallerFiles (.exe only). Keep a plain
# zip installer entry for URL/hash tracking without portable command claims.
if installer.get("InstallerType") not in (None, "zip"):
    # Allow InstallerType on the Installers[] entry instead of the root.
    pass
if installer.get("NestedInstallerFiles"):
    errors.append(
        f"{installer_path}: NestedInstallerFiles are not supported for this "
        "PowerShell package (WinGet portable allows .exe only)"
    )
if installer.get("PortableCommandAliases") is not None:
    errors.append(f"{installer_path}: PortableCommandAliases is not a valid WinGet field")

installers = installer.get("Installers")
if not isinstance(installers, list) or not installers:
    errors.append(f"{installer_path}: Installers must be a non-empty list")
else:
    entry = installers[0]
    itype = entry.get("InstallerType") or installer.get("InstallerType")
    if itype != "zip":
        errors.append(f"{installer_path}: InstallerType must be 'zip'")
    url = entry.get("InstallerUrl", "")
    if not isinstance(url, str) or not url.startswith("https://"):
        errors.append(f"{installer_path}: InstallerUrl must be an https URL")
    sha = str(entry.get("InstallerSha256", ""))
    if isinstance(entry.get("InstallerSha256"), int):
        sha = f"{entry['InstallerSha256']:064x}"
    if not re.fullmatch(r"[0-9a-fA-F]{64}", sha):
        errors.append(f"{installer_path}: InstallerSha256 must be 64 hex characters (got {sha!r})")
    commands = entry.get("Commands")
    if commands:
        errors.append(
            f"{installer_path}: omit Commands for zip-only manifests "
            "(portable multi-command is not supported without .exe)"
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
print("note: winget validate is skipped in CI (portable NestedInstallerFiles require .exe)")
PY

# --- Tip-of-main git package (not VERSION-gated) ---
GIT_DIR="packaging/winget-git"
GIT_ID="bolens.millenniumhelpers.git"
GIT_VERSION_FILE="$GIT_DIR/bolens.millenniumhelpers.git.yaml"
GIT_INSTALLER_FILE="$GIT_DIR/bolens.millenniumhelpers.git.installer.yaml"
GIT_LOCALE_FILE="$GIT_DIR/bolens.millenniumhelpers.git.locale.en-US.yaml"

for f in "$GIT_VERSION_FILE" "$GIT_INSTALLER_FILE" "$GIT_LOCALE_FILE"; do
  [[ -f "$f" ]] || fail "missing $f"
done

python3 - "$GIT_ID" "$GIT_VERSION_FILE" "$GIT_INSTALLER_FILE" "$GIT_LOCALE_FILE" <<'PY'
import re
import sys
from pathlib import Path

import yaml

expected_id, version_path, installer_path, locale_path = sys.argv[1:5]
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

for path, data in (
    (version_path, version),
    (installer_path, installer),
    (locale_path, locale),
):
    pid = data.get("PackageIdentifier")
    if pid != expected_id:
        errors.append(f"{path}: PackageIdentifier '{pid}' != '{expected_id}'")
    if not data.get("ManifestVersion"):
        errors.append(f"{path}: ManifestVersion is missing")

if version.get("ManifestType") != "version":
    errors.append(f"{version_path}: ManifestType must be 'version'")
if installer.get("ManifestType") != "installer":
    errors.append(f"{installer_path}: ManifestType must be 'installer'")
if locale.get("ManifestType") != "defaultLocale":
    errors.append(f"{locale_path}: ManifestType must be 'defaultLocale'")

installers = installer.get("Installers")
if not isinstance(installers, list) or not installers:
    errors.append(f"{installer_path}: Installers must be a non-empty list")
else:
    entry = installers[0]
    url = str(entry.get("InstallerUrl", ""))
    if "archive/refs/heads/main.zip" not in url:
        errors.append(f"{installer_path}: InstallerUrl must point at main.zip archive")
    sha = str(entry.get("InstallerSha256", ""))
    if isinstance(entry.get("InstallerSha256"), int):
        sha = f"{entry['InstallerSha256']:064x}"
    if not re.fullmatch(r"[0-9a-fA-F]{64}", sha):
        errors.append(f"{installer_path}: InstallerSha256 must be 64 hex characters")

for field in ("PackageName", "Publisher", "License", "ShortDescription"):
    if not locale.get(field):
        errors.append(f"{locale_path}: missing required field {field}")

if errors:
    for err in errors:
        print(f"::error::{err}", file=sys.stderr)
        print(f"error: {err}", file=sys.stderr)
    raise SystemExit(1)

print("Winget git (tip-of-main) manifest structural checks passed.")
PY
