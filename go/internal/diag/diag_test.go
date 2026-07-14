package diag

import (
	"path/filepath"
	"testing"
)

func TestRunReadOnly(t *testing.T) {
	t.Setenv("MILLENNIUM_CONFIG_DIR", t.TempDir())
	t.Setenv("MILLENNIUM_CONFIG_FILE", filepath.Join(t.TempDir(), "missing.json"))
	results := RunReadOnly()
	if len(results) < 2 {
		t.Fatalf("expected checks, got %d", len(results))
	}
	out := FormatReport(results)
	if !contains(out, "Helpers Version") {
		t.Fatalf("%s", out)
	}
}

func TestNeedsLegacy(t *testing.T) {
	if NeedsLegacy(nil) {
		t.Fatal("bare diag should be native")
	}
	if !NeedsLegacy([]string{"doctor"}) {
		t.Fatal("doctor needs legacy")
	}
	if !NeedsLegacy([]string{"--json"}) {
		t.Fatal("json needs legacy")
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
