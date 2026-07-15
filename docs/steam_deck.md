# Steam Deck & Flatpak Troubleshooting

Guidance for running Millennium Helpers on **Steam Deck** (SteamOS) and with
**Flatpak Steam** on desktop Linux. Full docs index: [README.md](README.md).
For general security and FAQ items, see
[security_troubleshooting.md](security_troubleshooting.md). Uninstall /
dry-run: [uninstall_dryrun.md](uninstall_dryrun.md). Licensing:
[licensing.md](licensing.md).

---

## Quick health check

On Deck or any Flatpak Steam host:

```bash
millennium diag
# or structured output:
millennium diag --json
```

Look for:

- **Bootstrap Hooks** — `libXtst.so.6` symlinks under your Steam `ubuntu12_32` / `ubuntu12_64` dirs
- **Flatpak Sandbox Override** — `/usr/lib/millennium` must be visible inside the Flatpak container
- **Permissions / skins** — ownership under `~/.local/share/Steam` or the Flatpak data tree

Auto-repair common issues:

```bash
sudo millennium diag doctor
# or:
sudo millennium repair
```

---

## Steam paths on Deck / Flatpak

Helpers probe several Steam roots. On Deck and Flatpak installs the important ones are:

| Layout | Typical path |
| --- | --- |
| Native / SteamOS | `~/.local/share/Steam` |
| Steam symlink tree | `~/.steam/steam` or `~/.steam/root` |
| Flatpak Steam | `~/.var/app/com.valvesoftware.Steam/.local/share/Steam` |
| Flatpak Millennium config | `~/.var/app/com.valvesoftware.Steam/config/millennium` (or `.config/millennium`) |

If `millennium diag` cannot find Steam, confirm which client you launch (native vs Flatpak) and that the matching directory exists.

---

## Flatpak sandbox override (required)

Flatpak Steam cannot load Millennium libraries from the host unless the sandbox
can see `/usr/lib/millennium`.

Grant the override (user scope):

```bash
flatpak override --user --filesystem=/usr/lib/millennium com.valvesoftware.Steam
```

`millennium diag doctor` applies this automatically when Flatpak Steam is detected
and the override is missing. Verify:

```bash
flatpak override --user --show com.valvesoftware.Steam
# should include filesystem=/usr/lib/millennium
```

After changing overrides, fully quit Steam and relaunch it.

---

## Steam Deck (SteamOS) notes

1. **Desktop Mode** — Install and run helpers from Desktop Mode (Konsole). Game Mode does not provide a normal package/admin workflow for these scripts.
2. **Password / sudo** — Set a sudo password in Desktop Mode if you have not already (`passwd`). System-wide install and upgrades need elevation.
3. **Install helpers** — Prefer a package manager when available, or:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/bolens/millenium-helpers/main/install.sh | sudo bash
   ```

   Prefer verifying a release checksum / using Nix, Homebrew (`Formula/millennium-helpers.rb`), or AUR when you can avoid curl-pipe.
4. **Read-only root** — SteamOS uses an immutable root. Millennium itself installs under `/usr/lib/millennium`; if writes fail after an OS update, re-run `sudo millennium upgrade` or `sudo millennium repair`, then `millennium diag`.
5. **Updates** — Deck OS updates can reset or conflict with custom system files. After a SteamOS update, run:

   ```bash
   millennium diag
   sudo millennium diag doctor
   ```

6. **Scheduler** — User systemd timers work in Desktop sessions; for background updates while logged out, enable lingering:

   ```bash
   loginctl enable-linger $USER
   millennium schedule status
   ```

7. **Games running** — Upgrade, repair, and purge refuse to proceed while a Steam game is active. Exit the game (and preferably Steam) first.

---

## Multi-library / SD card libraries

Steam may keep games on an SD card or secondary library, but Millennium hooks live
in the **client** Steam directory (bootstrap under `ubuntu12_*`), not inside each
game library folder. Point diagnostics at the client install Steam uses to launch,
not only the library on `/run/media/...`.

If you have multiple Steam installs (native + Flatpak), run `millennium diag` and
confirm hooks exist for the install you actually launch on Deck.

---

## Common Deck / Flatpak failures

### Millennium does not load in Flatpak Steam
1. Confirm binaries: `ls /usr/lib/millennium/version.txt`
2. Confirm override (see above)
3. Confirm hooks under the Flatpak Steam path point at `/usr/lib/millennium/...`
4. Run `sudo millennium repair` then relaunch Steam

### Blank / black Steam UI after upgrade
Clear CEF cache via repair:

```bash
sudo millennium repair
```

### Rate limits during upgrade on Deck Wi‑Fi
Set a GitHub token in config (`millennium schedule setup` or `config set github_token ...`)
or export `GITHUB_TOKEN` before upgrading.

### Purge / uninstall
```bash
sudo millennium purge --yes          # remove Millennium client hooks/files
sudo ./install.sh uninstall          # remove helpers only
```

Use `--dry-run` first if unsure.

---

## Related commands

| Command | Purpose |
| --- | --- |
| `millennium diag` | Health report / doctor / logs / share |
| `millennium repair` | Hooks, ownership, htmlcache, theme refresh |
| `millennium upgrade` | Install/update Millennium client |
| `millennium schedule` | Daily auto-update timer |
| `man millennium-diag` | Manual page (when man pages are installed) |

## Related

- **Docs index:** [README.md](README.md)
- **Project:** [README.md](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [SECURITY.md](../SECURITY.md)
- **Guides:** [security_troubleshooting.md](security_troubleshooting.md) · [uninstall_dryrun.md](uninstall_dryrun.md) · [licensing.md](licensing.md) · [mcp.md](mcp.md)
