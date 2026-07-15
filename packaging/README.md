# Packaging matrix

| Variant | Meaning | Typical source |
| --- | --- | --- |
| **from-source** (`millennium-helpers`) | Tagged `vX.Y.Z`, build Go when applicable | GitHub tag archive + `make build` |
| **bin** (`millennium-helpers-bin`) | Published release assets | `millennium-helpers-v{VER}-{os}-{arch}.tar.gz` / `.zip` |
| **git** (`millennium-helpers-git`) | Tip of `main` | VCS / `main.zip` / flake source |

**AUR-standard naming** applies on Arch, Homebrew, Scoop, Nix, deb, and rpm.
Winget and Chocolatey are **bin** (plus Winget **git**); they do not ship a from-source package.

| Channel | from-source | bin | git |
| --- | --- | --- | --- |
| Arch | `packaging/millennium-helpers/` | `packaging/millennium-helpers-bin/` | `packaging/millennium-helpers-git/` |
| Homebrew | `Formula/millennium-helpers.rb` (+ `head`) | `Formula/millennium-helpers-bin.rb` | `head` on source formula |
| Scoop | `packaging/scoop/millennium-helpers.json` | `…-bin.json` | `…-git.json` |
| Nix | `packages.millennium-helpers` | `…-bin` | `…-git` |
| Winget | — | `packaging/winget/` | `packaging/winget-git/` |
| deb | `packaging/deb/millennium-helpers/` + `build-from-source.sh` | `…-bin/` + `build-bin.sh` | tip build via from-source script |
| rpm | `packaging/rpm/millennium-helpers.spec` | `…-bin.spec` | tip via from-source `.spec` |
| Chocolatey | — | `packaging/chocolatey/millennium-helpers/` | — |

Release CD publishes versioned, OS/arch-trimmed bin packs (each embeds the
matching Go dispatcher), controlled `-src.tar.gz` / `-src.zip` trees for
from-source packaging, and standalone `millennium-v{VER}-{os}-{arch}` binaries.
There are no legacy unversioned asset aliases.
