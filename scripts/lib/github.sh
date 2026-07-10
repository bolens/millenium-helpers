# shellcheck shell=bash
# GitHub API interaction helpers for Millennium Helpers.
# Sourced by common.sh

_github_curl_headers() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "-H" "Authorization: token $GITHUB_TOKEN"
  fi
}

_github_explain_http_error() {
  local http_code="$1"
  local hdr_file="${2:-}"
  local rate_remaining=""
  local rate_reset=""

  if [[ -n "$hdr_file" && -f "$hdr_file" ]]; then
    rate_remaining=$(grep -i '^x-ratelimit-remaining:' "$hdr_file" 2>/dev/null | awk '{print $2}' | tr -d '\r' || true)
    rate_reset=$(grep -i '^x-ratelimit-reset:' "$hdr_file" 2>/dev/null | awk '{print $2}' | tr -d '\r' || true)
  fi

  case "$http_code" in
    401)
      echo "GitHub API returned HTTP 401 (unauthorized). Your token may be invalid or expired." >&2
      echo "Tip: set a PAT via 'millennium schedule setup' or 'millennium schedule config set github_token <token>'." >&2
      ;;
    403)
      if [[ "$rate_remaining" == "0" ]]; then
        echo "GitHub API rate limit exceeded (HTTP 403)." >&2
        if [[ -n "$rate_reset" ]]; then
          echo "Rate limit resets at epoch ${rate_reset}." >&2
        fi
      else
        echo "GitHub API returned HTTP 403 (forbidden / rate-limited)." >&2
      fi
      echo "Tip: set a PAT via 'millennium schedule setup' or 'millennium schedule config set github_token <token>'." >&2
      ;;
    404)
      echo "GitHub API returned HTTP 404 (not found). Check the repository name or release tag." >&2
      ;;
    000|"")
      echo "GitHub API request failed (network error or no response)." >&2
      ;;
    *)
      echo "GitHub API request failed (HTTP ${http_code})." >&2
      if [[ -n "$rate_remaining" ]]; then
        echo "Rate-limit remaining: ${rate_remaining}." >&2
      fi
      ;;
  esac
}

# GET a GitHub API URL; prints response body on stdout on success.
# On failure prints a helpful message to stderr and returns non-zero.
# Compatible with simple curl mocks that print the body to stdout and ignore -o/-w.
_github_api_get() {
  local url="$1"
  local headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi
  headers+=("-H" "User-Agent: millennium-helpers" "-H" "Accept: application/vnd.github+json")

  local tmp_body tmp_hdr
  tmp_body=$(mktemp 2>/dev/null || mktemp -t mh-gh-body.XXXXXX)
  tmp_hdr=$(mktemp 2>/dev/null || mktemp -t mh-gh-hdr.XXXXXX)

  local curl_rc=0
  local http_code
  http_code=$(curl -sL --retry 3 --retry-delay 2 -o "$tmp_body" -D "$tmp_hdr" -w "%{http_code}" \
    ${headers[@]+"${headers[@]}"} "$url" 2>/dev/null) || curl_rc=$?

  # Test mocks often echo JSON to stdout and ignore -o/-w. Detect that case.
  if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
    if [[ ! -s "$tmp_body" && -n "$http_code" ]]; then
      printf '%s' "$http_code" > "$tmp_body"
    fi
    local first
    first=$(head -c 1 "$tmp_body" 2>/dev/null || true)
    if [[ "$first" == "{" || "$first" == "[" ]]; then
      http_code="200"
      curl_rc=0
    elif [[ "$curl_rc" -ne 0 ]]; then
      http_code="000"
    else
      http_code="000"
    fi
  fi

  if [[ "$curl_rc" -ne 0 && "$http_code" == "200" && ! -s "$tmp_body" ]]; then
    http_code="000"
  fi

  if [[ "$http_code" != "200" ]]; then
    _github_explain_http_error "$http_code" "$tmp_hdr"
    rm -f "$tmp_body" "$tmp_hdr"
    return 1
  fi

  cat "$tmp_body"
  rm -f "$tmp_body" "$tmp_hdr"
  return 0
}

_github_parse_json() {
  local json="$1"
  local expr="$2"
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    expr = sys.argv[2]
    if expr == 'commit_sha':
        print(data[0].get('sha', '') if isinstance(data, list) and data else '')
    elif expr == 'latest_tag':
        print(data.get('tag_name', '') if isinstance(data, dict) else '')
    elif expr == 'beta_tag':
        if isinstance(data, list):
            for r in data:
                if r.get('prerelease') and 'beta' in r.get('tag_name', ''):
                    print(r['tag_name'])
                    break
except Exception:
    pass
" "$json" "$expr" 2>/dev/null || true
  else
    echo ""
  fi
}

fetch_github_commit() {
  local owner="$1"
  local repo="$2"
  local body
  if ! body=$(_github_api_get "https://api.github.com/repos/${owner}/${repo}/commits"); then
    return 0
  fi
  if command -v jq &>/dev/null; then
    printf '%s' "$body" | jq -r '.[0].sha' 2>/dev/null || true
  else
    _github_parse_json "$body" "commit_sha"
  fi
}

fetch_github_latest_stable_tag() {
  local owner="$1"
  local repo="$2"
  local body
  if ! body=$(_github_api_get "https://api.github.com/repos/${owner}/${repo}/releases/latest"); then
    return 0
  fi
  if command -v jq &>/dev/null; then
    printf '%s' "$body" | jq -r '.tag_name' 2>/dev/null || true
  else
    _github_parse_json "$body" "latest_tag"
  fi
}

fetch_github_latest_beta_tag() {
  local owner="$1"
  local repo="$2"
  local body
  if ! body=$(_github_api_get "https://api.github.com/repos/${owner}/${repo}/releases"); then
    return 0
  fi
  if command -v jq &>/dev/null; then
    printf '%s' "$body" | jq -r '.[] | select(.prerelease == true and (.tag_name | contains("beta"))) | .tag_name' 2>/dev/null | head -n 1 || true
  else
    _github_parse_json "$body" "beta_tag"
  fi
}
