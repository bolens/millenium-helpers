package mcp

import (
	"bytes"
	"strings"
	"testing"
)

func TestPythonStyleJSONSpaces(t *testing.T) {
	var buf bytes.Buffer
	err := writeJSONLine(&buf, map[string]any{"jsonrpc": "2.0", "id": 1})
	if err != nil {
		t.Fatal(err)
	}
	got := buf.String()
	if !strings.Contains(got, `"id": 1`) {
		t.Fatalf("expected spaced id key, got %q", got)
	}
	if !strings.HasSuffix(got, "\n") {
		t.Fatalf("expected trailing newline, got %q", got)
	}
}
