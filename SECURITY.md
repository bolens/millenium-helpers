# Security Policy

## Reporting a Vulnerability

Please report security issues privately via GitHub Security Advisories:

https://github.com/bolens/millenium-helpers/security/advisories/new

Do **not** open a public issue for vulnerabilities that could enable privilege escalation, supply-chain tampering, or credential theft.

Include:
- Affected version / commit
- Platform (Linux, macOS, Windows, Steam Deck)
- Steps to reproduce
- Impact assessment (if known)

We aim to acknowledge reports within a few days and ship fixes as quickly as practical.

## Security Design Overview

Millennium Helpers manages Steam Client homebrew installs and may elevate privileges for system-wide updates. Key controls:

- **Linux sudoers**: install configures a narrow NOPASSWD allow-list under `/etc/sudoers.d/millennium-helpers` for specific helper commands only
- **Write-protected scripts**: installed binaries are root-owned (`755`) so unprivileged users cannot rewrite them
- **Release integrity**: piped installers and Millennium upgrades verify SHA256 checksums from published `.sha256` sidecars before extracting archives
- **Config secrets**: `github_token` in helpers config is stored with restricted permissions (`chmod 600` on Unix; ACL lockdown on Windows)
- **MCP server**: tools that escalate or mutate the system require explicit confirmation / allow-lists (see `docs/mcp.md`)

For troubleshooting and deeper design notes, see [docs/security_troubleshooting.md](docs/security_troubleshooting.md).

## Supported Versions

Security fixes are applied to the latest release on `main`. Older tags are not generally backported unless a critical issue warrants it.
