package mcp

// Tool is an MCP tools/list entry.
type Tool struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	InputSchema map[string]any `json:"inputSchema"`
}

// ToolsList is the MCP tools/list catalog (contract-checked by check-cli-contract.py).
func ToolsList() []Tool {
	return []Tool{
		// @@cli-contract:mcp.tools@@
		{
			Name:        "millennium_diag",
			Description: "Run diagnostics to check the health of the Millennium client, themes, update timers, and configurations. Can optionally run in doctor mode to apply auto-repairs.",
			InputSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"doctor": map[string]any{
						"type":        "boolean",
						"description": "Set to true to run auto-repairs. Note: running doctor requires root/sudo privileges.",
					},
				},
			},
		},
		{
			Name:        "millennium_theme",
			Description: "Manage Millennium skins/themes (install, remove, list, update).",
			InputSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"action": map[string]any{
						"type":        "string",
						"enum":        []string{"list", "install", "remove", "update"},
						"description": "The action to perform.",
					},
					"theme": map[string]any{
						"type":        "string",
						"description": "Name or GitHub repository URL of the theme (required for install, remove, or updating a single theme).",
					},
					"all": map[string]any{
						"type":        "boolean",
						"description": "Update all themes (only applicable if action is 'update').",
					},
				},
				"required": []string{"action"},
			},
		},
		{
			Name:        "millennium_upgrade",
			Description: "Upgrade, reinstall, or roll back the Millennium client on the stable, beta, or main release channel.",
			InputSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"channel": map[string]any{
						"type":        "string",
						"enum":        []string{"stable", "beta", "main"},
						"description": "The release channel to upgrade to (defaults to stable).",
					},
					"force": map[string]any{
						"type":        "boolean",
						"description": "Force reinstalling or upgrading the client even if it is already up to date.",
					},
					"rollback": map[string]any{
						"type":        "string",
						"description": "Rollback option. Set to 'list' to view available backup directories, or specify a backup directory name to roll back to that state.",
					},
				},
			},
		},
		{
			Name:        "millennium_schedule",
			Description: "Configure the background update scheduler (enable systemd daily timer or cron job). On Linux, systemd prefers system units when privileged.",
			InputSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"action": map[string]any{
						"type":        "string",
						"enum":        []string{"enable", "disable", "status"},
						"description": "Scheduler action.",
					},
					"channel": map[string]any{
						"type":        "string",
						"enum":        []string{"stable", "beta", "main"},
						"description": "Release channel to target (only for 'enable').",
					},
					"cron": map[string]any{
						"type":        "boolean",
						"description": "Force using crontab instead of systemd.",
					},
					"system": map[string]any{
						"type":        "boolean",
						"description": "Linux: force systemd system units (requires root).",
					},
					"user": map[string]any{
						"type":        "boolean",
						"description": "Linux: force systemd user units.",
					},
				},
				"required": []string{"action"},
			},
		},
		{
			Name:        "millennium_repair",
			Description: "Force reinstalling or repairing the Millennium client (restores hooks and binaries).",
			InputSchema: map[string]any{
				"type":       "object",
				"properties": map[string]any{},
			},
		},
		{
			Name:        "millennium_purge",
			Description: "Uninstall and completely purge all Millennium client files, themes, and bootstrap hooks. Destructive: requires confirm=true.",
			InputSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"confirm": map[string]any{
						"type":        "boolean",
						"description": "Must be true to actually purge. Refuses otherwise.",
					},
					"dry_run": map[string]any{
						"type":        "boolean",
						"description": "If true, simulate the purge without deleting anything.",
					},
				},
				"required": []string{"confirm"},
			},
		},
		// @@/cli-contract:mcp.tools@@
	}
}
