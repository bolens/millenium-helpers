package mcp

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/bolens/millenium-helpers/internal/atomicfile"
)

const (
	mcpServerName = "millennium-helpers"
	mcpCommand    = "millennium"
)

// RegisterResult summarizes --register outcome.
type RegisterResult struct {
	RegisteredAny bool
	Lines         []string
}

type mcpHostConfig struct {
	Label string
	Path  string
	Key   string
}

func mcpHostConfigs() []mcpHostConfig {
	home, _ := os.UserHomeDir()
	claude := filepath.Join(home, ".config", "Claude", "claude_desktop_config.json")
	if runtime.GOOS == "windows" {
		if appdata := os.Getenv("APPDATA"); appdata != "" {
			claude = filepath.Join(appdata, "Claude", "claude_desktop_config.json")
		}
	}
	return []mcpHostConfig{
		{Label: "Claude Desktop", Path: claude, Key: "mcpServers"},
		{Label: "Windsurf", Path: filepath.Join(home, ".codeium", "windsurf", "mcp_config.json"), Key: "mcpServers"},
		{Label: "Cursor", Path: filepath.Join(home, ".cursor", "mcp.json"), Key: "mcpServers"},
	}
}

// Register writes millennium-helpers into detected AI client MCP configs.
func Register() RegisterResult {
	var out RegisterResult
	serverConfig := map[string]any{"command": mcpCommand, "args": []string{"mcp"}}

	for _, cfg := range mcpHostConfigs() {
		dir := filepath.Dir(cfg.Path)
		if st, err := os.Stat(dir); err != nil || !st.IsDir() {
			continue
		}

		out.Lines = append(out.Lines, fmt.Sprintf("Registering Millennium Helpers MCP server in %s...", cfg.Label))

		data := map[string]any{}
		if raw, err := os.ReadFile(cfg.Path); err == nil && len(raw) > 0 {
			if err := json.Unmarshal(raw, &data); err != nil {
				out.Lines = append(out.Lines, fmt.Sprintf(
					"  Error: existing config at %s is invalid JSON: %v. File left unchanged.", cfg.Path, err,
				))
				continue
			}
		}

		servers, _ := data[cfg.Key].(map[string]any)
		if servers == nil {
			servers = map[string]any{}
			data[cfg.Key] = servers
		}

		if existing, ok := servers[mcpServerName].(map[string]any); ok {
			args, _ := existing["args"].([]any)
			if cmd, _ := existing["command"].(string); cmd == mcpCommand && len(args) == 1 && args[0] == "mcp" {
				out.Lines = append(out.Lines, fmt.Sprintf("  Already registered in %s.", cfg.Label))
				out.RegisteredAny = true
				continue
			}
		}

		servers[mcpServerName] = serverConfig
		raw, err := json.MarshalIndent(data, "", "  ")
		if err != nil {
			out.Lines = append(out.Lines, fmt.Sprintf("  Error: failed to encode config for %s: %v", cfg.Path, err))
			continue
		}
		mode := os.FileMode(0o644)
		if st, err := os.Stat(cfg.Path); err == nil {
			mode = st.Mode().Perm()
		}
		if err := atomicfile.WriteFile(cfg.Path, append(raw, '\n'), mode); err != nil {
			out.Lines = append(out.Lines, fmt.Sprintf("  Error: failed to write config to %s: %v", cfg.Path, err))
			continue
		}
		out.Lines = append(out.Lines, fmt.Sprintf("  Successfully registered in %s config: %s", cfg.Label, cfg.Path))
		out.RegisteredAny = true
	}

	snippet, _ := json.MarshalIndent(map[string]any{
		"mcpServers": map[string]any{mcpServerName: serverConfig},
	}, "", "  ")
	out.Lines = append(out.Lines, "", "Manual config snippet (any MCP host):", string(snippet))

	if !out.RegisteredAny {
		out.Lines = append(out.Lines, "",
			"No active config directories found (Claude Desktop, Windsurf, or Cursor).",
			"Paste the snippet above into your MCP client's config file.")
	} else {
		out.Lines = append(out.Lines, "",
			"Registration check completed successfully.",
			"Restart Cursor / Claude Desktop / Windsurf so the MCP server appears.",
			"See docs/mcp.md for tool details and troubleshooting.")
	}
	return out
}

// RunRegister prints Register() output and returns the process exit code.
func RunRegister() int {
	res := Register()
	for _, line := range res.Lines {
		fmt.Println(line)
	}
	if !res.RegisteredAny {
		return 1
	}
	return 0
}
