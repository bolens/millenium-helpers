# shellcheck shell=bash
# Safe archive extraction helpers (zip-slip rejection).

# Extract a zip into dest_dir, refusing absolute paths, .. components, or
# members that would resolve outside dest_dir. Uses Python's zipfile for
# consistent behavior across platforms.
safe_extract_zip() {
  local zip_path="$1"
  local dest_dir="$2"
  if [[ -z "$zip_path" || -z "$dest_dir" ]]; then
    echo -e "${RED}Error: safe_extract_zip requires zip path and destination directory.${NC}" >&2
    return 1
  fi
  if [[ ! -f "$zip_path" ]]; then
    echo -e "${RED}Error: Zip archive not found: ${zip_path}${NC}" >&2
    return 1
  fi
  mkdir -p "$dest_dir" || return 1
  python3 - "$zip_path" "$dest_dir" <<'PY'
import os
import sys
import zipfile

zip_path, dest_dir = sys.argv[1], sys.argv[2]
dest_real = os.path.realpath(dest_dir)

def is_safe(member: str) -> bool:
    # Normalize separators; reject absolute and drive paths.
    name = member.replace("\\", "/")
    if not name or name.endswith("/"):
        # Directory entries are fine if the name itself is safe.
        name = name.rstrip("/")
        if not name:
            return True
    if name.startswith("/") or (len(name) >= 2 and name[1] == ":"):
        return False
    parts = name.split("/")
    if any(p == ".." for p in parts):
        return False
    target = os.path.realpath(os.path.join(dest_real, *parts))
    return target == dest_real or target.startswith(dest_real + os.sep)

try:
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            if not is_safe(info.filename):
                print(
                    f"Error: Refusing zip member with unsafe path: {info.filename!r}",
                    file=sys.stderr,
                )
                sys.exit(1)
        zf.extractall(dest_dir)
except zipfile.BadZipFile as e:
    print(f"Error: Invalid zip archive: {e}", file=sys.stderr)
    sys.exit(1)
except OSError as e:
    print(f"Error: Failed to extract zip: {e}", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
}
