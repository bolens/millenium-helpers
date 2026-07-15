# Documentation

Index of Millennium Helpers docs. `make check-docs` enforces that this index,
the project [README](../README.md) **Further reading** table, and each guide’s
**Related** section stay cross-linked.

## Guides

| Doc | Audience | Summary |
| --- | --- | --- |
| [licensing.md](licensing.md) | Users & packagers | Helpers MIT + Millennium client MIT, vendored notice, upgrade behavior |
| [mcp.md](mcp.md) | Users | MCP server tools, registration with Claude / Cursor / Windsurf |
| [security_troubleshooting.md](security_troubleshooting.md) | Users | Sudoers / Task Scheduler design, common failures |
| [steam_deck.md](steam_deck.md) | Users | Steam Deck (SteamOS) and Flatpak Steam hooks / overrides |
| [uninstall_dryrun.md](uninstall_dryrun.md) | Users | Dry-run mode and manual uninstall per install method |
| [release_runbook.md](release_runbook.md) | Maintainers | Cutting a `vX.Y.Z` release (preflight → tag → packaging) |

## Project root docs

| Doc | Summary |
| --- | --- |
| [README.md](../README.md) | Install, commands, config, further reading |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Dev requirements, layout, versioning, packaging, licensing |
| [packaging/README.md](../packaging/README.md) | from-source / bin / git packaging matrix (Arch, brew, Scoop, Nix, deb, rpm, Chocolatey) |
| [SECURITY.md](../SECURITY.md) | Vulnerability reporting and security design overview |
| [CHANGELOG.md](../CHANGELOG.md) | Release notes |
| [LICENSE](../LICENSE) | Millennium Helpers MIT license |
| [third_party/](../third_party/README.md) | Vendored third-party notices (Millennium client) |

## Manual pages

Installed with the helpers (`man millennium`, `man millennium-diag`, …). Each page
has a `LICENSE` section pointing at [licensing.md](licensing.md); command-specific
pages also point at the matching guide where one exists (for example
`millennium-mcp(1)` → [mcp.md](mcp.md)).

## Keeping links in sync

1. Add or rename a guide under `docs/` → update **this index**, [README § Further reading](../README.md#further-reading), and topical **Related** footers.
2. Run `make check-docs` (includes licensing checks; also part of `make lint` / `make check-all`).

## Related

- [Project README](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [SECURITY.md](../SECURITY.md) · [CHANGELOG.md](../CHANGELOG.md) · [licensing.md](licensing.md)
