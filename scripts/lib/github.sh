# shellcheck shell=bash
# GitHub API interaction helpers for Millennium Helpers.
# Sourced by common.sh

_github_curl_headers() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "-H" "Authorization: token $GITHUB_TOKEN"
  fi
}

fetch_github_commit() {
  local owner="$1"
  local repo="$2"
  local headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi

  if command -v jq &>/dev/null; then
    curl -fsSL --retry 3 --retry-delay 2 "${headers[@]}" \
      "https://api.github.com/repos/${owner}/${repo}/commits" | jq -r '.[0].sha' || true
  else
    python3 -c "
import urllib.request, json, os
try:
    headers = {'User-Agent': 'Mozilla/5.0'}
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization'] = f'token {token}'
    req = urllib.request.Request('https://api.github.com/repos/${owner}/${repo}/commits', headers=headers)
    with urllib.request.urlopen(req) as response:
        print(json.loads(response.read().decode())[0].get('sha', ''))
except Exception:
    pass
" || true
  fi
}

fetch_github_latest_stable_tag() {
  local owner="$1"
  local repo="$2"
  local headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi

  if command -v jq &>/dev/null; then
    curl -sL --retry 3 --retry-delay 2 "${headers[@]}" \
      "https://api.github.com/repos/${owner}/${repo}/releases/latest" | jq -r '.tag_name' || true
  else
    python3 -c "
import urllib.request, json, os
try:
    headers = {'User-Agent': 'Mozilla/5.0'}
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization'] = f'token {token}'
    req = urllib.request.Request('https://api.github.com/repos/${owner}/${repo}/releases/latest', headers=headers)
    with urllib.request.urlopen(req) as response:
        print(json.loads(response.read().decode()).get('tag_name', ''))
except Exception:
    pass
" || true
  fi
}

fetch_github_latest_beta_tag() {
  local owner="$1"
  local repo="$2"
  local headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("-H" "Authorization: token $GITHUB_TOKEN")
  fi

  if command -v jq &>/dev/null; then
    curl -sL --retry 3 --retry-delay 2 "${headers[@]}" \
      "https://api.github.com/repos/${owner}/${repo}/releases" \
      | jq -r '.[] | select(.prerelease == true and (.tag_name | contains("beta"))) | .tag_name' \
      | head -n 1 || true
  else
    python3 -c "
import urllib.request, json, os
try:
    headers = {'User-Agent': 'Mozilla/5.0'}
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization'] = f'token {token}'
    req = urllib.request.Request('https://api.github.com/repos/${owner}/${repo}/releases', headers=headers)
    with urllib.request.urlopen(req) as response:
        releases = json.loads(response.read().decode())
        for r in releases:
            if r.get('prerelease') and 'beta' in r.get('tag_name', ''):
                print(r['tag_name'])
                break
except Exception:
    pass
" || true
  fi
}
