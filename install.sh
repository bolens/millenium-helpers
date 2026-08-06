#!/usr/bin/env bash
# Thin bootstrap: ensure bin/millennium, then exec `millennium install|uninstall`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pre-parse track/tag for piped mode (before a source tree exists).
_PIPE_TRACK="${MILLENNIUM_HELPERS_TRACK:-release}"
_PIPE_TAG="${MILLENNIUM_HELPERS_TAG:-}"
_PIPE_ALLOW_UNSIGNED_MAIN=false
_pre_args=("$@")
while [[ ${#_pre_args[@]} -gt 0 ]]; do
  case "${_pre_args[0]}" in
    --track)
      _PIPE_TRACK="${_pre_args[1]:-}"
      _pre_args=("${_pre_args[@]:2}")
      ;;
    --track=*)
      _PIPE_TRACK="${_pre_args[0]#*=}"
      _pre_args=("${_pre_args[@]:1}")
      ;;
    --tag)
      _PIPE_TAG="${_pre_args[1]:-}"
      _PIPE_TRACK="tag"
      _pre_args=("${_pre_args[@]:2}")
      ;;
    --tag=*)
      _PIPE_TAG="${_pre_args[0]#*=}"
      _PIPE_TRACK="tag"
      _pre_args=("${_pre_args[@]:1}")
      ;;
    --allow-unsigned-main)
      _PIPE_ALLOW_UNSIGNED_MAIN=true
      _pre_args=("${_pre_args[@]:1}")
      ;;
    *)
      _pre_args=("${_pre_args[@]:1}")
      ;;
  esac
done
[[ -n "$_PIPE_TAG" ]] && _PIPE_TRACK="tag"
_PIPE_TRACK="$(printf '%s' "$_PIPE_TRACK" | tr '[:upper:]' '[:lower:]')"

# Standalone/piped: no checkout VERSION next to this script → download & re-exec.
if [[ ! -f "${SCRIPT_DIR}/VERSION" ]]; then
    echo "Running in standalone/piped mode. Downloading helpers (track=${_PIPE_TRACK})..."
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    HELPERS_REPO="${HELPERS_GITHUB_REPO:-bolens/millenium-helpers}"
    IS_SOURCE=0
    if [[ -n "${MILLENNIUM_HELPERS_RELEASE_URL:-}" ]]; then
      RELEASE_URL="$MILLENNIUM_HELPERS_RELEASE_URL"
      SHA_URL="${MILLENNIUM_HELPERS_RELEASE_SHA_URL:-${RELEASE_URL}.sha256}"
      NEEDS_SHA=1
    else
      case "$_PIPE_TRACK" in
        main)
          if [[ "$_PIPE_ALLOW_UNSIGNED_MAIN" != "true" && "${MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN:-}" != "1" ]]; then
            echo "Error: --track main requires --allow-unsigned-main" >&2
            exit 1
          fi
          RELEASE_URL="https://github.com/${HELPERS_REPO}/archive/refs/heads/main.tar.gz"
          SHA_URL=""
          NEEDS_SHA=0
          IS_SOURCE=1
          ;;
        tag|release|*)
          _pipe_arch=amd64
          case "$(uname -m 2>/dev/null || echo x86_64)" in
            aarch64 | arm64) _pipe_arch=arm64 ;;
          esac
          if [[ "$_PIPE_TRACK" == "tag" ]]; then
            _tag="${_PIPE_TAG#v}"
            [[ -n "$_tag" ]] || { echo "Error: --tag required for track=tag" >&2; exit 1; }
          else
            _tag="$(
              curl -fsSL --max-filesize 4194304 --retry 2 --retry-delay 1 \
                -H "User-Agent: millennium-helpers" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/${HELPERS_REPO}/releases/latest" 2>/dev/null \
                | python3 -c "import json,sys; print((json.load(sys.stdin).get('tag_name') or '').lstrip('v'))" 2>/dev/null \
                || true
            )"
            [[ -n "$_tag" ]] || { echo "Error: could not resolve latest release tag" >&2; exit 1; }
          fi
          RELEASE_URL="https://github.com/${HELPERS_REPO}/releases/download/v${_tag}/millennium-helpers-v${_tag}-linux-${_pipe_arch}.tar.gz"
          SHA_URL="${RELEASE_URL}.sha256"
          NEEDS_SHA=1
          ;;
      esac
    fi

    ARCHIVE="$TEMP_DIR/helpers-download.tar.gz"
    curl -fsSL --max-filesize 536870912 "$RELEASE_URL" -o "$ARCHIVE" || {
      echo "Error: Failed to download $RELEASE_URL" >&2
      exit 1
    }
    if [[ "$NEEDS_SHA" -eq 1 ]]; then
      SHA_FILE="$TEMP_DIR/helpers.sha256"
      curl -fsSL --max-filesize 4096 "$SHA_URL" -o "$SHA_FILE" || {
        echo "Error: Failed to download $SHA_URL" >&2
        exit 1
      }
      EXPECTED_SHA=$(awk '{print $1; exit}' "$SHA_FILE" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
      ACTUAL_SHA=$(sha256sum "$ARCHIVE" | awk '{print $1}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
      [[ "$EXPECTED_SHA" == "$ACTUAL_SHA" ]] || {
        echo "Error: SHA256 mismatch" >&2
        exit 1
      }
    fi
    python3 - "$ARCHIVE" "$TEMP_DIR" <<'PY'
import os
import pathlib
import shutil
import sys
import tarfile

archive, destination = sys.argv[1:]
base = pathlib.Path(destination).resolve()
max_entries = 100_000
max_expanded = 1 << 30
with tarfile.open(archive, "r:gz") as bundle:
    members = bundle.getmembers()
    if len(members) > max_entries:
        raise SystemExit("Error: archive contains too many entries")
    total = 0
    for member in members:
        path = pathlib.PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or "\\" in member.name:
            raise SystemExit(f"Error: unsafe archive path: {member.name}")
        if not (member.isdir() or member.isfile()):
            raise SystemExit(f"Error: unsupported archive entry: {member.name}")
        total += member.size
        if total > max_expanded:
            raise SystemExit("Error: expanded archive exceeds size limit")
        target = (base / pathlib.Path(*path.parts)).resolve()
        if os.path.commonpath((base, target)) != str(base):
            raise SystemExit(f"Error: archive entry escapes destination: {member.name}")
    for member in members:
        target = base / pathlib.Path(*pathlib.PurePosixPath(member.name).parts)
        if member.isdir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        source = bundle.extractfile(member)
        if source is None:
            raise SystemExit(f"Error: could not read archive entry: {member.name}")
        with source, target.open("wb") as output:
            shutil.copyfileobj(source, output, length=1024 * 1024)
        target.chmod(member.mode & 0o777)
PY
    EXTRACT_ROOT="$TEMP_DIR"
    if [[ "$IS_SOURCE" -eq 1 ]]; then
      for cand in "$TEMP_DIR"/millenium-helpers-main "$TEMP_DIR"/millenium-helpers-*; do
        if [[ -f "${cand}/install.sh" ]]; then
          EXTRACT_ROOT="$cand"
          break
        fi
      done
    fi
    export MILLENNIUM_HELPERS_TRACK="$_PIPE_TRACK"
    [[ -n "$_PIPE_TAG" ]] && export MILLENNIUM_HELPERS_TAG="$_PIPE_TAG"
    export MILLENNIUM_HELPERS_SOURCE_URL="$RELEASE_URL"
    exec bash "$EXTRACT_ROOT/install.sh" "$@"
fi

ensure_millennium() {
  if [[ -n "${MILLENNIUM_BOOTSTRAP_BIN:-}" ]]; then
    if [[ -x "$MILLENNIUM_BOOTSTRAP_BIN" ]]; then
      printf '%s' "$MILLENNIUM_BOOTSTRAP_BIN"
      return 0
    fi
    echo "Error: MILLENNIUM_BOOTSTRAP_BIN is not executable: $MILLENNIUM_BOOTSTRAP_BIN" >&2
    exit 1
  fi
  local out="${SCRIPT_DIR}/bin/millennium"
  if [[ -x "$out" ]]; then
    printf '%s' "$out"
    return 0
  fi
  if [[ -d "${SCRIPT_DIR}/go/cmd/millennium" ]] && command -v go >/dev/null 2>&1; then
    make -C "${SCRIPT_DIR}" build >/dev/null
  fi
  if [[ -x "$out" ]]; then
    printf '%s' "$out"
    return 0
  fi
  echo "Error: Go dispatcher bin/millennium is required (run make build)." >&2
  exit 1
}

GO_BIN="$(ensure_millennium)"
export MILLENNIUM_SOURCE_ROOT="${MILLENNIUM_SOURCE_ROOT:-$SCRIPT_DIR}"

# Map legacy install.sh verbs onto millennium install|uninstall.
action="install"
forward=()
for arg in "$@"; do
  case "$arg" in
    install|-i|--install)
      action="install"
      ;;
    uninstall|-u|--uninstall)
      action="uninstall"
      ;;
    -h|--help)
      exec "$GO_BIN" install --help
      ;;
    -V|--version)
      exec "$GO_BIN" version
      ;;
    *)
      forward+=("$arg")
      ;;
  esac
done

exec "$GO_BIN" "$action" "${forward[@]+"${forward[@]}"}"
