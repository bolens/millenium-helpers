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

func TestPythonStyleJSONPreservesColonsInsideStrings(t *testing.T) {
	got := string(pythonStyleJSON([]byte(`{"url":"https://example.com","n":1}`)))
	if !strings.Contains(got, `"url": "https://example.com"`) {
		t.Fatalf("space after key colon: %q", got)
	}
	if !strings.Contains(got, `https://example.com`) || strings.Contains(got, `https: //`) {
		t.Fatalf("must not space colon inside string: %q", got)
	}
	if !strings.Contains(got, `"n": 1`) {
		t.Fatalf("space after second key: %q", got)
	}
}
