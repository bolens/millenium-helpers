#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034 # HELPERS_* globals are set for callers (install.sh / diag)
# Helpers install track resolution, install-meta.json read/write, and legacy migrate.
# Sourced by install.sh (after common.sh) and diag modules.
#
# Tracks: release | main | tag | checkout
# See CONTRIBUTING.md § Versioning / install tracks.

HELPERS_GITHUB_REPO="${HELPERS_GITHUB_REPO:-bolens/millenium-helpers}"
HELPERS_INSTALL_META_NAME="install-meta.json"

# shellcheck source=scripts/lib/release_assets.sh
_INSTALL_TRACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_INSTALL_TRACK_DIR}/release_assets.sh"

# Globals set by resolve_helpers_install_track / helpers_install_meta_*:
# HELPERS_TRACK, HELPERS_TRACK_REF, HELPERS_TRACK_VERSION, HELPERS_TRACK_URL,
# HELPERS_TRACK_SHA_URL, HELPERS_TRACK_NEEDS_SHA, HELPERS_TRACK_IS_SOURCE_ARCHIVE

helpers_install_meta_path() {
  local lib_dir="${1:-${MILLENNIUM_LIB_DIR:-/usr/local/lib/millennium-helpers}}"
  printf '%s/%s' "${lib_dir%/}" "$HELPERS_INSTALL_META_NAME"
}

# Normalize tag to vX.Y.Z form.
helpers_normalize_tag() {
  local tag="${1:-}"
  tag="${tag#v}"
  [[ -n "$tag" ]] || return 1
  printf 'v%s' "$tag"
}

# Resolve track from CLI/env into HELPERS_TRACK_* globals.
# Args: optional --track VALUE --tag VALUE (already parsed by caller into env/vars).
# Usage: resolve_helpers_install_track [track] [tag]
#   track: release|main|tag (default release, or MILLENNIUM_HELPERS_TRACK)
#   tag:   vX.Y.Z when track=tag (or MILLENNIUM_HELPERS_TAG)
resolve_helpers_install_track() {
  local track="${1:-${MILLENNIUM_HELPERS_TRACK:-release}}"
  local tag="${2:-${MILLENNIUM_HELPERS_TAG:-}}"
  local platform="${3:-linux}" # linux|windows

  track="$(printf '%s' "$track" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$tag" ]]; then
    track="tag"
  fi

  case "$track" in
    release|main|tag|checkout) ;;
    *)
      echo "error: invalid helpers track '$track' (expected release|main|tag)" >&2
      return 1
      ;;
  esac

  HELPERS_TRACK="$track"
  HELPERS_TRACK_REF=""
  HELPERS_TRACK_VERSION=""
  HELPERS_TRACK_URL=""
  HELPERS_TRACK_SHA_URL=""
  HELPERS_TRACK_NEEDS_SHA=0
  HELPERS_TRACK_IS_SOURCE_ARCHIVE=0

  # Explicit URL override wins for download (track still recorded).
  if [[ -n "${MILLENNIUM_HELPERS_RELEASE_URL:-}" ]]; then
    HELPERS_TRACK_URL="$MILLENNIUM_HELPERS_RELEASE_URL"
    HELPERS_TRACK_SHA_URL="${MILLENNIUM_HELPERS_RELEASE_SHA_URL:-${HELPERS_TRACK_URL}.sha256}"
    HELPERS_TRACK_NEEDS_SHA=1
    case "$track" in
      tag)
        HELPERS_TRACK_REF="$(helpers_normalize_tag "$tag" 2>/dev/null || printf '%s' "$tag")"
        HELPERS_TRACK_VERSION="${HELPERS_TRACK_REF#v}"
        ;;
      main)
        HELPERS_TRACK_REF="main"
        HELPERS_TRACK_IS_SOURCE_ARCHIVE=1
        HELPERS_TRACK_NEEDS_SHA=0
        ;;
      *)
        HELPERS_TRACK_REF="latest"
        ;;
    esac
    return 0
  fi

  helpers_bin_asset_for_version() {
    local ver="$1"
    local arch
    if [[ "$platform" == "windows" ]]; then
      release_asset_helpers "$ver" windows amd64 zip
      return 0
    fi
    arch="$(release_host_arch)" || return 1
    # install.sh Unix path uses linux packs (darwin installs typically use Homebrew).
    release_asset_helpers "$ver" linux "$arch" tar.gz
  }

  case "$track" in
    release)
      local latest_tag asset
      latest_tag="$(release_fetch_latest_tag "$HELPERS_GITHUB_REPO")" || {
        echo "error: could not resolve latest GitHub release tag for ${HELPERS_GITHUB_REPO}" >&2
        return 1
      }
      HELPERS_TRACK_REF="$latest_tag"
      HELPERS_TRACK_VERSION="${latest_tag#v}"
      asset="$(helpers_bin_asset_for_version "$HELPERS_TRACK_VERSION")" || return 1
      HELPERS_TRACK_URL="https://github.com/${HELPERS_GITHUB_REPO}/releases/download/${latest_tag}/${asset}"
      HELPERS_TRACK_SHA_URL="${HELPERS_TRACK_URL}.sha256"
      HELPERS_TRACK_NEEDS_SHA=1
      ;;
    tag)
      local norm asset
      norm="$(helpers_normalize_tag "$tag")" || {
        echo "error: --tag / MILLENNIUM_HELPERS_TAG required for track=tag (got '$tag')" >&2
        return 1
      }
      HELPERS_TRACK_REF="$norm"
      HELPERS_TRACK_VERSION="${norm#v}"
      asset="$(helpers_bin_asset_for_version "$HELPERS_TRACK_VERSION")" || return 1
      HELPERS_TRACK_URL="https://github.com/${HELPERS_GITHUB_REPO}/releases/download/${norm}/${asset}"
      HELPERS_TRACK_SHA_URL="${HELPERS_TRACK_URL}.sha256"
      HELPERS_TRACK_NEEDS_SHA=1
      ;;
    main)
      HELPERS_TRACK_REF="main"
      HELPERS_TRACK_IS_SOURCE_ARCHIVE=1
      HELPERS_TRACK_NEEDS_SHA=0
      if [[ "$platform" == "windows" ]]; then
        HELPERS_TRACK_URL="https://github.com/${HELPERS_GITHUB_REPO}/archive/refs/heads/main.zip"
      else
        HELPERS_TRACK_URL="https://github.com/${HELPERS_GITHUB_REPO}/archive/refs/heads/main.tar.gz"
      fi
      ;;
    checkout)
      HELPERS_TRACK_REF="checkout"
      ;;
  esac
  return 0
}

write_helpers_install_meta() {
  local lib_dir="${1:?lib dir required}"
  local track="${2:?track required}"
  local ref="${3:-}"
  local version="${4:-}"
  local source_url="${5:-}"
  local migrated_from="${6:-}"
  local path
  path="$(helpers_install_meta_path "$lib_dir")"
  local installed_at
  installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

  mkdir -p "$lib_dir" 2>/dev/null || true
  python3 - "$path" "$track" "$ref" "$version" "$source_url" "$installed_at" "$migrated_from" <<'PY'
import json, sys
from pathlib import Path

path, track, ref, version, source_url, installed_at, migrated_from = sys.argv[1:8]
data = {
    "track": track,
    "ref": ref or None,
    "version": version or None,
    "source_url": source_url or None,
    "installed_at": installed_at,
    "migrated_from": migrated_from or None,
}
try:
    Path(path).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
except PermissionError:
    sys.exit(1)
except OSError as exc:
    print(f"warning: could not write install-meta.json: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

read_helpers_install_meta() {
  local lib_dir="${1:-${MILLENNIUM_LIB_DIR:-/usr/local/lib/millennium-helpers}}"
  local path
  path="$(helpers_install_meta_path "$lib_dir")"
  HELPERS_META_TRACK=""
  HELPERS_META_REF=""
  HELPERS_META_VERSION=""
  HELPERS_META_SOURCE_URL=""
  [[ -f "$path" ]] || return 1
  eval "$(python3 - "$path" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
def q(s):
    s = "" if s is None else str(s)
    return "'" + s.replace("'", "'\"'\"'") + "'"
print(f"HELPERS_META_TRACK={q(data.get('track'))}")
print(f"HELPERS_META_REF={q(data.get('ref'))}")
print(f"HELPERS_META_VERSION={q(data.get('version'))}")
print(f"HELPERS_META_SOURCE_URL={q(data.get('source_url'))}")
PY
)"
  return 0
}

# Infer track for legacy installs; write meta. Args: lib_dir, install_method hint, optional checkout path.
# install_method: manual|pacman|pacman-git|scoop|scoop-git|winget|winget-git|checkout|none
migrate_helpers_install_meta_if_needed() {
  local lib_dir="${1:-${MILLENNIUM_LIB_DIR:-/usr/local/lib/millennium-helpers}}"
  local method="${2:-manual}"
  local checkout="${3:-}"
  local path
  path="$(helpers_install_meta_path "$lib_dir")"
  if [[ -f "$path" ]]; then
    return 0
  fi

  local track="release" ref="" version=""
  version="$(tr -d '[:space:]' < "${lib_dir}/VERSION" 2>/dev/null || true)"
  case "$method" in
    pacman-git|scoop-git|winget-git|main)
      track="main"
      ref="main"
      ;;
    checkout)
      track="checkout"
      if [[ -n "$checkout" && -d "${checkout}/.git" ]]; then
        ref="$(git -C "$checkout" rev-parse --short HEAD 2>/dev/null || echo checkout)"
      else
        ref="checkout"
      fi
      ;;
    pacman|scoop|winget|manual|release|"")
      track="release"
      if [[ -n "$version" ]]; then
        ref="v${version}"
      else
        ref="latest"
      fi
      ;;
    *)
      track="release"
      ref="${version:+v$version}"
      ref="${ref:-latest}"
      ;;
  esac

  write_helpers_install_meta "$lib_dir" "$track" "$ref" "$version" "" "legacy" || return 1
  return 0
}

# Fetch tip commit SHA for main branch (best-effort).
helpers_fetch_main_commit_sha() {
  local repo="${1:-$HELPERS_GITHUB_REPO}"
  local body=""
  body=$(curl -fsSL --retry 2 --retry-delay 1 \
    -H "User-Agent: millennium-helpers" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/commits/main" 2>/dev/null || true)
  [[ -n "$body" ]] || return 1
  python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('sha',''))" "$body" 2>/dev/null || true
}
