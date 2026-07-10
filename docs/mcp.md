# Model Context Protocol (MCP) Server

The Millennium Helper suite includes a built-in Model Context Protocol (MCP) server that exposes the entire command suite as native AI tools to coding assistants (such as Claude Desktop, Cursor, Windsurf, or Antigravity).

For general usage instructions, see the main [README.md](../README.md). For troubleshooting and security details, see [security_troubleshooting.md](security_troubleshooting.md).

---

## Exposed MCP Tools

| Tool Name | Description | Parameters |
| --- | --- | --- |
| `millennium_diag` | Runs read-only diagnostics or applies auto-repairs in doctor mode. | `doctor` (boolean, optional): set `true` to auto-repair. |
| `millennium_theme` | Manages theme/skin directories (list, install, remove, update). | `action` (string, required): `list`, `install`, `remove`, `update`. <br> `theme` (string, optional): repo or name. <br> `all` (boolean, optional): update all themes. |
| `millennium_upgrade` | Upgrades, reinstalls, or rolls back the Millennium client system-wide. | `channel` (string, optional): `stable` (default) or `beta`. <br> `force` (boolean, optional): force reinstall/upgrade. <br> `rollback` (string, optional): list backups ('list') or specify backup name to roll back to. |
| `millennium_schedule` | Manages background auto-update timers. | `action` (string, required): `enable`, `disable`, `status`. <br> `channel` (string, optional): `stable` or `beta`. <br> `cron` (boolean, optional): force crontab (Linux only). |
| `millennium_repair` | Runs system-wide permissions and symlink repairs. | None. |
| `millennium_purge` | Completely uninstalls all Millennium client hooks and files. | None. (MCP always passes `--yes` / `-Yes` so agents are not blocked by the interactive confirmation.) |

---

## Configuration & Registration

### Automatic Registration

To automatically register the `millennium-mcp` server with installed AI tools (Claude Desktop, Windsurf, and Cursor), run:

```bash
millennium-mcp --register
```

This detects the config folders for Claude Desktop, Windsurf, and Cursor (`~/.cursor/mcp.json`), updates or creates the JSON configuration files, and adds the `millennium-helpers` server automatically.

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
