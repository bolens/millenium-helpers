# Changelog

All notable changes to Millennium Helpers are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.1] - 2026-07-10

### Security
- Verify SHA256 checksums in piped `install.sh` / `install.ps1` against release `.sha256` sidecars
- Verify SHA256 checksums during Windows `millennium-upgrade` (parity with Linux)
- Restrict Windows `config.json` ACLs when writing `github_token`

### Fixed
- Include `scripts/millennium-mcp.py` in the trimmed Windows release zip / Scoop CI staging
- Update standalone installer tests for trimmed release archive layout
- Republish release assets so packaging checksums match the Windows zip that includes MCP

### Changed
- Wire `test_millennium_dispatcher.sh` and `test_packaging_ci.sh` into the CI matrix
- Slim local `tests/run_tests.sh` to source shared assertions and defer packaging gates to CI

## [2.2.0] - 2026-07-09

See GitHub release notes for v2.2.0.
