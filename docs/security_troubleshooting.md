# Security Design & Troubleshooting

This document outlines the security architecture and troubleshooting steps for the Millennium Helper utility suite.

For general usage instructions, see the main [README.md](../README.md). For MCP server setup details, see [mcp.md](mcp.md).

---

## Security Design

To allow background user-level timers to run updates that modify system directories, the updater scripts must run with elevated privileges.

This setup achieves this securely:
1. **Sudoers Autoconfiguration (Linux)**: During `sudo ./install.sh`, the installer detects the original invoking user (`SUDO_USER`) and automatically configures a secure drop-in file at `/etc/sudoers.d/millennium-helpers`.
2. **Write-Protected Scripts**: Helper scripts are copied into `/usr/local/bin/` owned by `root:root` with `755` permissions, meaning normal users cannot edit or tamper with them.
3. **Task Scheduler (Windows)**: Scheduled tasks are registered with elevated credentials using native Windows Task Scheduler security boundaries.

---

## Troubleshooting & FAQ

### Steam shows a blank/black screen after upgrading Millennium
This is usually caused by outdated CEF cached files. Run the repair utility to fix local permissions and clear Steam's htmlcache:
```bash
# Linux
sudo millennium-repair

# Windows
millennium-repair
```

### The background timer is not running updates
1. Check the timer status:
   ```bash
   millennium-schedule status
   ```
2. Verify that passwordless sudo (Linux) or Scheduled Tasks (Windows) are configured correctly.
3. If you want the updates to run even when you are logged out of your session on Linux, enable user lingering:
   ```bash
   loginctl enable-linger $USER
   ```

### Steam Deck or Flatpak Steam issues
Hooks, sandbox overrides, Desktop Mode install, and post-SteamOS-update recovery are covered in the [Steam Deck & Flatpak Troubleshooting](steam_deck.md) guide.
