# Model Context Protocol (MCP) Server

The Millennium Helper suite includes a built-in Model Context Protocol (MCP) server that exposes the entire command suite as native AI tools to coding assistants (such as Claude Desktop, Cursor, Windsurf, or Antigravity).

For general usage instructions, see the main [README.md](../README.md). Full
docs index: [README.md](README.md). For troubleshooting and security details,
see [security_troubleshooting.md](security_troubleshooting.md). Licensing:
[licensing.md](licensing.md).

---

## Exposed MCP Tools

| Tool Name | Description | Parameters |
| --- | --- | --- |
| `millennium_diag` | Runs read-only diagnostics or applies auto-repairs in doctor mode. | `doctor` (boolean, optional): set `true` to auto-repair. |
| `millennium_theme` | Manages theme/skin directories (list, install, remove, update). | `action` (string, required): `list`, `install`, `remove`, `update`. <br> `theme` (string, optional): repo or name. <br> `all` (boolean, optional): update all themes. |
| `millennium_upgrade` | Upgrades, reinstalls, or rolls back the Millennium client system-wide. | `channel` (string, optional): `stable` (default), `beta`, or `main` (client channel — not the helpers install track). <br> `force` (boolean, optional): force reinstall/upgrade. <br> `rollback` (string, optional): list backups ('list') or specify backup name to roll back to. |
| `millennium_schedule` | Manages background auto-update timers. | `action` (string, required): `enable`, `disable`, `status`. <br> `channel` (string, optional): client channel `stable`, `beta`, or `main`. <br> `cron` (boolean, optional): force crontab (Linux only). |
| `millennium_repair` | Runs system-wide permissions and symlink repairs. | None. |
| `millennium_purge` | Completely uninstalls all Millennium client hooks and files. | `confirm` (boolean, required): must be `true` to purge. <br> `dry_run` (boolean, optional): simulate without deleting. Escalates via `sudo -n` / elevated PowerShell like the other write tools. |

**Helpers track vs client channel:** MCP `channel` arguments always mean the Millennium **client** `update_channel` (`stable` / `beta` / `main`). Helpers install track (`release` / `main` / `tag`) is chosen at install time (`millennium install --track`, or Unix `install.sh --track`) and is not an MCP tool parameter.

**Go MCP server:** `millennium mcp` (and PATH `millennium-mcp` argv0 twin) is the
stdio JSON-RPC server and owns `--register`. Dual-OS `go.yml` smokes `initialize`.
Packaging installs the Go binary (or a thin shim) as `millennium-mcp`. Tool calls
self-exec `millennium <feature> …`, including elevating doctor/upgrade/repair/purge
(`sudo -n` / UAC). Force long-name helpers with `MILLENNIUM_MCP_LONGNAMES=1`.

**Safety gates (server-side):**
- `action` / `channel` values are allow-listed independently of the JSON schema (clients can send arbitrary strings)
- `theme` / `rollback` strings are character-class validated; path traversal (`..`) is refused
- `millennium_purge` requires `confirm=true` (or `dry_run=true`)
- Elevated Windows runs use Base64 `-EncodedCommand` + `-File` argument arrays (no shell `ArgumentList` string interpolation)
- Internal schedule hooks `pre-update` / `post-update` are not exposed as MCP actions

Doctor mode (`millennium_diag` with `doctor=true`) escalates and may rewrite helpers; overwriting root-owned scripts still requires the underlying CLI `--yes` confirmation path.

---

## Configuration & Registration

### Automatic Registration

To automatically register the `millennium-mcp` server with installed AI tools (Claude Desktop, Windsurf, and Cursor), run:

```bash
millennium-mcp --register
```

This detects the config folders for Claude Desktop, Windsurf, and Cursor (`~/.cursor/mcp.json`), updates or creates the JSON configuration files, and adds the `millennium-helpers` server automatically. It also prints a copy-paste JSON snippet for any other MCP host.

### Manual Configuration

To manually enable these tools in your AI assistant, configure the `millennium-mcp` command:

#### Claude Desktop
Add `millennium-helpers` to your Claude Desktop configuration file:
* **Linux**: `~/.config/Claude/claude_desktop_config.json`
* **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "millennium-helpers": {
      "command": "millennium-mcp"
    }
  }
}
```

#### Cursor
`millennium-mcp --register` writes `~/.cursor/mcp.json` when `~/.cursor` exists. You can also add it manually:

```json
{
  "mcpServers": {
    "millennium-helpers": {
      "command": "millennium-mcp"
    }
  }
}
```

Or use **Settings → MCP → Add New MCP Server** with command `millennium-mcp`.

#### Windsurf
Go to Settings -> Features -> MCP, click **+ Add New MCP Server**, and configure:
- **Name**: `millennium-helpers`
- **Type**: `command`
- **Command**: `millennium-mcp`

## Related

- **Docs index:** [README.md](README.md)
- **Project:** [README.md](../README.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) · [SECURITY.md](../SECURITY.md)
- **Guides:** [licensing.md](licensing.md) · [security_troubleshooting.md](security_troubleshooting.md) · [uninstall_dryrun.md](uninstall_dryrun.md) · [steam_deck.md](steam_deck.md)
