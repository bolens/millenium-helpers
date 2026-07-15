## Summary
<!-- What does this PR change and why? -->

## Checklist
- [ ] Linux and Windows behavior updated together (or contract-marked OS-only knob noted below)
- [ ] If flags/commands changed: [`spec/cli-contract.yaml`](spec/cli-contract.yaml) updated first (`make sync-cli-facade` / `make check-cli-contract`)
- [ ] `--help` / `-Help` and completions updated if flags changed
- [ ] Man page updated if a user-facing command changed (`make check-man`)
- [ ] Tests added or updated (`make check-all` / Pester / `make test-go`)
- [ ] Docs updated if user-facing (keep [docs/README.md](docs/README.md) + Related footers in sync; `make check-docs`)
- [ ] Packaging manifests touched only when intentional (Formula / Scoop / Winget / Nix / PKGBUILD)

## Intentional platform gaps
<!-- Delete if none. Only contract-marked OS-only knobs (e.g. schedule --cron). -->

## Test plan
- [ ] `make check-all`
- [ ] <!-- platform-specific: Pester, make test-go, brew audit, scoop install, etc. -->

See [CONTRIBUTING.md](https://github.com/bolens/millenium-helpers/blob/main/CONTRIBUTING.md) for layout and parity expectations.
