# shellcheck shell=bash
# Versioned GitHub Release asset names for millennium-helpers.
# Sourced by release CD, install_track, and packaging CI helpers.
#
# Bin:  millennium-helpers-v{VER}-{os}-{arch}.{tar.gz|zip}
# Src:  millennium-helpers-v{VER}-src.{tar.gz|zip}
# Go:   millennium-v{VER}-{os}-{arch}[.exe]

release_asset_helpers() {
  local version="${1:?version}" os="${2:?os}" arch="${3:?arch}" ext="${4:?ext}"
  version="${version#v}"
  printf 'millennium-helpers-v%s-%s-%s.%s' "$version" "$os" "$arch" "$ext"
}

release_asset_src() {
  local version="${1:?version}" ext="${2:?ext}"
  version="${version#v}"
  printf 'millennium-helpers-v%s-src.%s' "$version" "$ext"
}

release_asset_go() {
  local version="${1:?version}" os="${2:?os}" arch="${3:?arch}"
  local suffix=""
  version="${version#v}"
  if [[ "$os" == "windows" ]]; then
    suffix=".exe"
  fi
  printf 'millennium-v%s-%s-%s%s' "$version" "$os" "$arch" "$suffix"
}

# Map uname -m → Go/release arch label (amd64|arm64).
release_host_arch() {
  local m
  m="$(uname -m 2>/dev/null || echo x86_64)"
  case "$m" in
    x86_64 | amd64) printf 'amd64' ;;
    aarch64 | arm64) printf 'arm64' ;;
    *)
      echo "error: unsupported machine arch '$m' (expected x86_64/amd64 or aarch64/arm64)" >&2
      return 1
      ;;
  esac
}

# Map uname -s → goos for helpers bin packs (linux|darwin).
release_host_unix_os() {
  local s
  s="$(uname -s 2>/dev/null || echo Linux)"
  case "$s" in
    Linux) printf 'linux' ;;
    Darwin) printf 'darwin' ;;
    *)
      echo "error: unsupported unix OS '$s' (expected Linux or Darwin)" >&2
      return 1
      ;;
  esac
}

# Resolve latest GitHub release tag (vX.Y.Z). Prints tag or returns non-zero.
release_fetch_latest_tag() {
  local repo="${1:-bolens/millenium-helpers}"
  local body tag
  body=$(curl -fsSL --retry 2 --retry-delay 1 \
    -H "User-Agent: millennium-helpers" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null || true)
  [[ -n "$body" ]] || return 1
  tag="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('tag_name','') or '')" "$body" 2>/dev/null || true)"
  [[ -n "$tag" ]] || return 1
  printf '%s' "$tag"
}
