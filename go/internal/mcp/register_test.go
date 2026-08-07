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
	args, _ := entry["args"].([]any)
	if entry["command"] != "millennium" || len(args) != 1 || args[0] != "mcp" {
		t.Fatalf("cursor command: %#v", entry)
	}
}

func TestRegisterPreservesInvalidConfig(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)
	t.Setenv("APPDATA", filepath.Join(home, "AppData"))

	cursorDir := filepath.Join(home, ".cursor")
	if err := os.MkdirAll(cursorDir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(cursorDir, "mcp.json")
	const invalid = "{not-json\n"
	if err := os.WriteFile(path, []byte(invalid), 0o644); err != nil {
		t.Fatal(err)
	}

	res := Register()
	if res.RegisteredAny {
		t.Fatalf("invalid-only config should not register: %v", res.Lines)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != invalid {
		t.Fatalf("invalid config was overwritten: %q", raw)
	}
}
