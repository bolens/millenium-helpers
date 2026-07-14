# Licensing

Canonical licensing notes for Millennium Helpers and the Millennium client these
tools install. Keep this page, the README **License** section, man-page
`LICENSE` sections, and `third_party/` in sync — `make check-docs` enforces
the cross-links (see also the [docs index](README.md)).

| Artifact | What it covers |
| --- | --- |
| [`LICENSE`](../LICENSE) | **Millennium Helpers** (this repo) — MIT, Copyright © bolens |
| [`third_party/MILLENNIUM-LICENSE.md`](../third_party/MILLENNIUM-LICENSE.md) | Vendored copy of the **Millennium client** MIT notice |
| [Upstream `LICENSE.md`](https://github.com/SteamClientHomebrew/Millennium/blob/main/LICENSE.md) | Source of truth for Project Millennium’s license text |
| [`third_party/README.md`](../third_party/README.md) | Why vendored third-party notices live here |

## Summary

- **Helpers** (scripts, packaging recipes, MCP server, docs in this repo) are MIT —
  see [`LICENSE`](../LICENSE). User-facing overview: [README § License](../README.md#license).
- **Millennium** (the Steam Client homebrew framework from
  [SteamClientHomebrew/Millennium](https://github.com/SteamClientHomebrew/Millennium))
  is a **separate** project, also MIT-licensed by Project Millennium. Installing or
  upgrading it via these helpers is subject to Millennium’s terms.
- This project is **not affiliated with or endorsed by** SteamClientHomebrew,
  Project Millennium, or Valve Corporation. Steam® is a trademark of Valve Corporation.

## On install / upgrade

`millennium-upgrade` (Linux and Windows) places a copy of Millennium’s MIT notice
as `LICENSE` next to the installed client binaries. That satisfies MIT’s requirement
to include the copyright and permission notice with redistributed copies. Release
packages for Millennium itself do not always ship a license file inside the archive;
helpers supply the vendored text (or fetch upstream, or use an embedded fallback).

Implementation: `scripts/lib/millennium_license.sh` and
`Install-MillenniumLicense` in `scripts/windows/common.ps1`. The vendored file is
installed beside the helpers (e.g. `/usr/lib/millennium-helpers/MILLENNIUM-LICENSE.md`)
via `install.sh`, Homebrew, Nix, Arch PKGBUILDs, and the Windows installer.

## Docs & man pages

| Surface | Role |
| --- | --- |
| [README § License](../README.md#license) | Short user-facing summary |
| `man millennium(1)`, `man millennium-upgrade(1)`, … | Per-command `LICENSE` sections (all point here) |
| [CONTRIBUTING.md](../CONTRIBUTING.md#licensing) | Maintainer rules for keeping attribution in sync |
| [SECURITY.md](../SECURITY.md) | Security policy (links here for legal boundary) |
| Winget locale descriptions | Brief Millennium MIT attribution for store listings |

## Related docs

- **Docs index:** [README.md](README.md)
- **Project:** [README.md](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md#licensing) · [SECURITY.md](../SECURITY.md)
- **Guides:** [MCP server](mcp.md) · [Security design & troubleshooting](security_troubleshooting.md) · [Steam Deck & Flatpak](steam_deck.md) · [Uninstall / dry-run](uninstall_dryrun.md) · [Release runbook](release_runbook.md)

## Keeping this in sync

When changing license text, attribution, or how upgrade installs notices:

1. Update upstream-facing links and the vendored file (`third_party/MILLENNIUM-LICENSE.md`).
2. Update this page and [README § License](../README.md#license).
3. Confirm man-page `LICENSE` sections still reference this doc.
4. Run `make check-docs` (also part of `make lint` / `make check-all`).
