package mcp

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestRegisterWritesCursorAndClaude(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)
	t.Setenv("APPDATA", filepath.Join(home, "AppData"))

	claudeDir := filepath.Join(home, ".config", "Claude")
	cursorDir := filepath.Join(home, ".cursor")
	if err := os.MkdirAll(claudeDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(cursorDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(claudeDir, "claude_desktop_config.json"), []byte("{}\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	res := Register()
	if !res.RegisteredAny {
		t.Fatalf("expected registration, lines=%v", res.Lines)
	}

	raw, err := os.ReadFile(filepath.Join(cursorDir, "mcp.json"))
	if err != nil {
		t.Fatal(err)
	}
	var cursor map[string]any
	if err := json.Unmarshal(raw, &cursor); err != nil {
		t.Fatal(err)
	}
	servers, _ := cursor["mcpServers"].(map[string]any)
	entry, _ := servers["millennium-helpers"].(map[string]any)
	if entry["command"] != "millennium-mcp" {
		t.Fatalf("cursor command: %#v", entry)
	}
}
