## Summary
<!-- What does this PR change and why? -->

## Checklist
- [ ] Linux and Windows behavior updated together (or intentional gap noted below)
- [ ] `--help` / `-Help` and completions updated if flags changed
- [ ] Man page updated if a user-facing command changed (`make check-man`)
- [ ] Tests added or updated (`make check-all` / Pester)
- [ ] Docs updated if user-facing (keep [docs/README.md](docs/README.md) + Related footers in sync; `make check-docs`)
- [ ] Packaging manifests touched only when intentional (Formula / Scoop / Winget / Nix / PKGBUILD)

## Intentional platform gaps
<!-- Delete if none. Example: "schedule enable is Linux-only (systemd)." -->

## Test plan
- [ ] `make check-all`
- [ ] <!-- platform-specific: Pester, brew audit, scoop install, etc. -->

See [CONTRIBUTING.md](https://github.com/bolens/millenium-helpers/blob/main/CONTRIBUTING.md) for layout and parity expectations.
