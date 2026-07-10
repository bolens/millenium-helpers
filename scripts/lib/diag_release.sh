# shellcheck shell=bash
# shellcheck disable=SC2034 # status globals read by millennium-diag.sh / doctor
# Latest GitHub release tag and tarball fetch for diag sync

fetch_latest_release_tag() {
  LATEST_RELEASE_TAG=""
  LATEST_RELEASE_VERSION=""
  latest_sha="main"

  local api_url="https://api.github.com/repos/${HELPERS_REPO}/releases/latest"
  local api_data=""
  api_data=$(curl -sL --retry 3 --retry-delay 2 "$api_url" 2>/dev/null || true)
  [[ -n "$api_data" ]] || return 1

  local tag_name=""
  tag_name="$(_diag_parse_json_field "$api_data" "tag_name")"
  [[ -n "$tag_name" ]] || return 1

  LATEST_RELEASE_TAG="$tag_name"
  LATEST_RELEASE_VERSION="${tag_name#v}"
  latest_sha="$tag_name"
  return 0
}

diag_fetch_release_tarball() {
  if [[ -n "${DIAG_TEST_RELEASE_EXTRACT:-}" ]]; then
    DIAG_RELEASE_EXTRACT="$DIAG_TEST_RELEASE_EXTRACT"
    return 0
  fi

  DIAG_RELEASE_EXTRACT=""
  _diag_cleanup_release_workdir

  DIAG_RELEASE_WORKDIR=$(mktemp -d)
  if [[ -z "$DIAG_RELEASE_WORKDIR" || ! -d "$DIAG_RELEASE_WORKDIR" ]]; then
    echo -e "${RED}Error: Failed to create temporary directory for release tarball.${NC}" >&2
    return 1
  fi

  local track="${HELPERS_TRACK:-release}"
  local archive="${DIAG_RELEASE_WORKDIR}/helpers-archive.tar.gz"
  local sha_file="${DIAG_RELEASE_WORKDIR}/helpers-archive.tar.gz.sha256"
  local extract_dir="${DIAG_RELEASE_WORKDIR}/extract"
  local url=""

  case "$track" in
    main)
      url="https://github.com/${HELPERS_REPO}/archive/refs/heads/main.tar.gz"
      ;;
    tag)
      local tag_ref="${HELPERS_TRACK_REF:-}"
      [[ -n "$tag_ref" ]] || tag_ref="${LATEST_RELEASE_TAG:-}"
      [[ -n "$tag_ref" ]] || return 1
      url="https://github.com/${HELPERS_REPO}/releases/download/${tag_ref}/millennium-helpers-linux.tar.gz"
      ;;
    *)
      local tag="${LATEST_RELEASE_TAG:-}"
      if [[ -z "$tag" ]]; then
        fetch_latest_release_tag || true
        tag="${LATEST_RELEASE_TAG:-}"
      fi
      [[ -n "$tag" ]] || return 1
      url="https://github.com/${HELPERS_REPO}/releases/download/${tag}/millennium-helpers-linux.tar.gz"
      ;;
  esac

  if ! curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$archive" 2>/dev/null; then
    _diag_cleanup_release_workdir
    return 1
  fi

  if [[ "$track" != "main" ]]; then
    if curl -fsSL --retry 3 --retry-delay 2 "${url}.sha256" -o "$sha_file" 2>/dev/null; then
      if [[ -s "$sha_file" ]] && command -v sha256sum >/dev/null 2>&1; then
        (
          cd "$DIAG_RELEASE_WORKDIR" || exit 1
          sha256sum -c "$(basename "$sha_file")" >/dev/null 2>&1
        ) || {
          _diag_cleanup_release_workdir
          return 1
        }
      fi
    fi
  fi

  mkdir -p "$extract_dir" || {
    _diag_cleanup_release_workdir
    return 1
  }

  if ! tar -xzf "$archive" -C "$extract_dir" 2>/dev/null; then
    _diag_cleanup_release_workdir
    return 1
  fi

  # Source archives nest under millenium-helpers-main/
  if [[ "$track" == "main" ]]; then
    local nested
    for nested in "$extract_dir"/millenium-helpers-main "$extract_dir"/millenium-helpers-*; do
      if [[ -d "$nested/scripts" ]]; then
        DIAG_RELEASE_EXTRACT="$nested"
        return 0
      fi
    done
  fi

  DIAG_RELEASE_EXTRACT="$extract_dir"
  return 0
}

_diag_release_source_path() {
  local remote_rel="$1"
  if [[ -n "${DIAG_RELEASE_EXTRACT:-}" && -f "${DIAG_RELEASE_EXTRACT}/${remote_rel}" ]]; then
    echo "${DIAG_RELEASE_EXTRACT}/${remote_rel}"
    return 0
  fi
  return 1
}

_diag_fetch_remote_to_tmp() {
  local remote_rel="$1"
  local tmp_dest="$2"
  local tag="${LATEST_RELEASE_TAG:-main}"
  local remote_url="https://raw.githubusercontent.com/${HELPERS_REPO}/${tag}/${remote_rel}"

  curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" \
    --retry 3 --retry-delay 2 "$remote_url" -o "$tmp_dest" 2>/dev/null
}
