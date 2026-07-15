#!/usr/bin/env python3
"""Rewrite millennium-helpers-git PKGBUILD for CI --noextract builds.

Drops the multiline VCS source entry and keeps only the sudoers file, with a
matching sha256sums entry. Used by .github/workflows/pkgbuild.yml so PR CI can
build the checked-out tree without cloning github.com main.
"""

from __future__ import annotations

import pathlib
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(
            f"usage: {sys.argv[0]} PKGBUILD_PATH SUDOERS_SHA256",
            file=sys.stderr,
        )
        return 2

    path = pathlib.Path(sys.argv[1])
    checksum = sys.argv[2]
    text = path.read_text()
    text, n_src = re.subn(
        r"^source=\(.*?\)\n",
        'source=("millennium-helpers.sudoers")\n',
        text,
        count=1,
        flags=re.M | re.S,
    )
    text, n_sum = re.subn(
        r"^sha256sums=\(.*?\)\n",
        f"sha256sums=('{checksum}')\n",
        text,
        count=1,
        flags=re.M | re.S,
    )
    if n_src != 1 or n_sum != 1:
        print(
            f"failed to rewrite PKGBUILD source/sha256sums (src={n_src}, sum={n_sum})",
            file=sys.stderr,
        )
        return 1
    path.write_text(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
