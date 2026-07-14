package mcp

import (
	"strings"
	"testing"
)

func TestHandleToolCallValidation(t *testing.T) {
	r := HandleToolCall("millennium_theme", map[string]any{"action": "rm -rf"})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "invalid action") {
		t.Fatalf("theme action: %+v", r)
	}

	r = HandleToolCall("millennium_theme", map[string]any{"action": "install", "theme": "../../bad"})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "invalid characters") {
		t.Fatalf("theme path: %+v", r)
	}

	r = HandleToolCall("millennium_schedule", map[string]any{"action": "pre-update"})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "invalid action") {
		t.Fatalf("schedule internal: %+v", r)
	}

	r = HandleToolCall("millennium_upgrade", map[string]any{"channel": "nightly"})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "invalid channel") {
		t.Fatalf("upgrade channel: %+v", r)
	}

	r = HandleToolCall("millennium_purge", map[string]any{})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "confirm=true") {
		t.Fatalf("purge confirm: %+v", r)
	}

	r = HandleToolCall("not_a_real_tool", map[string]any{})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "Unknown tool") {
		t.Fatalf("unknown: %+v", r)
	}
}

func TestFeatureArgvLongNames(t *testing.T) {
	t.Setenv("MILLENNIUM_MCP_LONGNAMES", "1")
	got := FeatureArgv("diag", "--json")
	if len(got) < 2 || got[0] != "millennium-diag" || got[1] != "--json" {
		t.Fatalf("got %v", got)
	}
}

func TestFeatureArgvSelfExec(t *testing.T) {
	t.Setenv("MILLENNIUM_MCP_LONGNAMES", "")
	t.Setenv("MILLENNIUM_LEGACY", "")
	prev := osExecutable
	osExecutable = func() (string, error) { return "/opt/millennium", nil }
	defer func() { osExecutable = prev }()

	got := FeatureArgv("diag", "--json")
	if len(got) != 3 || got[0] != "/opt/millennium" || got[1] != "diag" || got[2] != "--json" {
		t.Fatalf("got %v", got)
	}
}
