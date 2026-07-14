#!/usr/bin/env bash
# Run govulncheck against the Go module (pinned via go run).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT/go"

GOVULNCHECK_VERSION="${GOVULNCHECK_VERSION:-v1.1.4}"

go run "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}" ./...
