# shellcheck shell=bash
# Install Project Millennium's MIT license notice next to client binaries.
# Sourced by common.sh.
# Docs: docs/licensing.md
# Upstream: https://github.com/SteamClientHomebrew/Millennium/blob/main/LICENSE.md
# Vendored: third_party/MILLENNIUM-LICENSE.md

MILLENNIUM_LICENSE_URL="https://raw.githubusercontent.com/SteamClientHomebrew/Millennium/main/LICENSE.md"

# Resolve a local vendored copy shipped with the helpers (preferred).
find_millennium_license_source() {
  local candidates=()
  local script_root
  script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd 2>/dev/null || true)"

  if [[ -n "$script_root" ]]; then
    candidates+=("${script_root}/third_party/MILLENNIUM-LICENSE.md")
  fi
  candidates+=(
    "${_COMMON_SCRIPT_DIR:-}/../third_party/MILLENNIUM-LICENSE.md"
    "${_COMMON_LIB_DIR:-}/../third_party/MILLENNIUM-LICENSE.md"
    "${_COMMON_LIB_DIR:-}/MILLENNIUM-LICENSE.md"
    "/usr/local/lib/millennium-helpers/third_party/MILLENNIUM-LICENSE.md"
    "/usr/lib/millennium-helpers/third_party/MILLENNIUM-LICENSE.md"
    "/usr/local/lib/millennium-helpers/MILLENNIUM-LICENSE.md"
    "/usr/lib/millennium-helpers/MILLENNIUM-LICENSE.md"
  )
  if command -v brew >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [[ -n "$brew_prefix" ]]; then
      candidates+=(
        "${brew_prefix}/lib/millennium-helpers/third_party/MILLENNIUM-LICENSE.md"
        "${brew_prefix}/lib/millennium-helpers/MILLENNIUM-LICENSE.md"
      )
    fi
  fi

  local path
  for path in "${candidates[@]}"; do
    [[ -n "$path" && -f "$path" ]] || continue
    echo "$path"
    return 0
  done
  return 1
}

# Embedded fallback matching upstream LICENSE.md / third_party/MILLENNIUM-LICENSE.md.
millennium_license_fallback_text() {
  cat <<'EOF'
MIT License

Copyright (c) 2026 Project Millennium

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
}

# Write Millennium's license notice into DEST_DIR/LICENSE (mode 644).
# Best-effort: never fails the upgrade if writing is impossible.
install_millennium_license() {
  local dest_dir="${1:?dest dir required}"
  local dest="${dest_dir%/}/LICENSE"
  local src=""
  local tmp=""

  if [[ ! -d "$dest_dir" ]]; then
    echo "Warning: Cannot install Millennium LICENSE — missing directory: ${dest_dir}" >&2
    return 0
  fi

  src="$(find_millennium_license_source || true)"
  if [[ -n "$src" ]]; then
    if install -m644 "$src" "$dest" 2>/dev/null || cp -f "$src" "$dest" 2>/dev/null; then
      chmod 644 "$dest" 2>/dev/null || true
      return 0
    fi
  fi

  tmp="$(mktemp)"
  if curl -fsSL --retry 2 --retry-delay 1 --max-time 15 "$MILLENNIUM_LICENSE_URL" -o "$tmp" 2>/dev/null \
    && [[ -s "$tmp" ]]; then
    if install -m644 "$tmp" "$dest" 2>/dev/null || cp -f "$tmp" "$dest" 2>/dev/null; then
      chmod 644 "$dest" 2>/dev/null || true
      rm -f "$tmp"
      return 0
    fi
  fi
  rm -f "$tmp"

  if millennium_license_fallback_text >"$dest" 2>/dev/null; then
    chmod 644 "$dest" 2>/dev/null || true
  fi
}
