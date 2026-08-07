package mcp

import (
	"os"
	"path/filepath"
	"runtime"
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

	r = HandleToolCall("millennium_config", map[string]any{"action": "disable-errors"})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "confirm=true") {
		t.Fatalf("config confirm: %+v", r)
	}

	r = HandleToolCall("millennium_config", map[string]any{"action": "enable", "names": []any{"../bad"}})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "invalid characters") {
		t.Fatalf("config name: %+v", r)
	}

	r = HandleToolCall("millennium_config", map[string]any{"action": "disable-errors", "dry_run": true, "plugins_only": true, "themes_only": true})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "cannot both") {
		t.Fatalf("config scopes: %+v", r)
	}

	for _, args := range []map[string]any{
		{"action": "show", "plugins_only": true},
		{"action": "plugins", "confirm": true},
		{"action": "errors", "dry_run": true},
	} {
		r = HandleToolCall("millennium_config", args)
		if !r.IsError || !strings.Contains(r.Content[0]["text"], "only valid") {
			t.Fatalf("config irrelevant option args=%v result=%+v", args, r)
		}
	}

	r = HandleToolCall("not_a_real_tool", map[string]any{})
	if !r.IsError || !strings.Contains(r.Content[0]["text"], "Unknown tool") {
		t.Fatalf("unknown: %+v", r)
	}
}

func TestValidClientName(t *testing.T) {
	for _, name := range []string{"gratitude", "extendium", "green-theme", "plugin0"} {
		if !validClientName(name) {
			t.Errorf("valid name rejected: %q", name)
		}
	}
	for _, name := range []string{"", ".", "..", "bad/name", "bad\\name", "bad\x00name", "bad\rname", "bad\nname"} {
		if validClientName(name) {
			t.Errorf("invalid name accepted: %q", name)
		}
	}
}

func TestConfigToolDispatch(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell mock is Unix-only")
	}
	dir := t.TempDir()
	mock := filepath.Join(dir, "millennium")
	if err := os.WriteFile(mock, []byte("#!/bin/sh\nprintf '%s\\n' \"$*\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("TEST_SUITE_RUN", "1")
	t.Setenv("MOCK_BIN", dir)
	previous := osExecutable
	osExecutable = func() (string, error) { return mock, nil }
	t.Cleanup(func() { osExecutable = previous })

	for _, test := range []struct {
		name string
		args map[string]any
		want string
	}{
		{name: "read errors JSON", args: map[string]any{"action": "errors"}, want: "config errors --json"},
		{name: "enable names", args: map[string]any{"action": "enable", "names": []any{"alpha", "beta"}}, want: "config enable alpha beta"},
		{name: "plugins dry run", args: map[string]any{"action": "disable-errors", "dry_run": true, "plugins_only": true}, want: "config disable-errors --plugins-only --dry-run"},
		{name: "themes confirmed", args: map[string]any{"action": "disable-errors", "confirm": true, "themes_only": true}, want: "config disable-errors --themes-only --yes"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := HandleToolCall("millennium_config", test.args)
			if result.IsError || !strings.Contains(result.Content[0]["text"], test.want) {
				t.Fatalf("result=%+v want=%q", result, test.want)
			}
		})
	}
}

func TestConfigToolSchema(t *testing.T) {
	for _, tool := range ToolsList() {
		if tool.Name != "millennium_config" {
			continue
		}
		properties, ok := tool.InputSchema["properties"].(map[string]any)
		if !ok {
			t.Fatal("millennium_config properties missing")
		}
		names, ok := properties["names"].(map[string]any)
		if !ok || names["type"] != "array" {
			t.Fatalf("names schema: %#v", properties["names"])
		}
		items, ok := names["items"].(map[string]any)
		if !ok || items["type"] != "string" {
			t.Fatalf("names items schema: %#v", names["items"])
		}
		return
	}
	t.Fatal("millennium_config tool missing")
}

func TestFeatureArgvSelfExec(t *testing.T) {
	prev := osExecutable
	osExecutable = func() (string, error) { return "/opt/millennium", nil }
	defer func() { osExecutable = prev }()

	got := FeatureArgv("diag", "--json")
	if len(got) != 3 || got[0] != "/opt/millennium" || got[1] != "diag" || got[2] != "--json" {
		t.Fatalf("got %v", got)
	}
}
