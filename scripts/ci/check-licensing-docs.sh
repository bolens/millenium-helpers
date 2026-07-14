#!/usr/bin/env bash
# Thin alias — full graph lives in check-docs-crosslinks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "${ROOT}/scripts/ci/check-docs-crosslinks.sh"
