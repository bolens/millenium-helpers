package mcp

import (
	"bytes"
	"strings"
	"testing"
)

func TestServeStdioInitializeAndToolsList(t *testing.T) {
	in := strings.NewReader(
		`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}` + "\n" +
			`{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}` + "\n",
	)
	var out bytes.Buffer
	if err := ServeStdio(in, &out); err != nil {
		t.Fatal(err)
	}
	got := out.String()
	if !strings.Contains(got, `"protocolVersion"`) {
		t.Fatalf("missing protocolVersion: %s", got)
	}
	if !strings.Contains(got, `"id": 1`) {
		t.Fatalf("missing spaced id: %s", got)
	}
	for _, tool := range []string{
		"millennium_diag", "millennium_theme", "millennium_upgrade",
		"millennium_schedule", "millennium_repair", "millennium_purge",
	} {
		if !strings.Contains(got, `"`+tool+`"`) {
			t.Fatalf("missing tool %s in %s", tool, got)
		}
	}
}

func TestServeStdioUnknownMethod(t *testing.T) {
	in := strings.NewReader(`{"jsonrpc":"2.0","id":3,"method":"not/a/real/method","params":{}}` + "\n")
	var out bytes.Buffer
	if err := ServeStdio(in, &out); err != nil {
		t.Fatal(err)
	}
	got := out.String()
	if !strings.Contains(got, `"error"`) || !strings.Contains(got, "-32601") {
		t.Fatalf("expected method not found: %s", got)
	}
}
