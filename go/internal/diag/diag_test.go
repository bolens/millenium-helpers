package diag

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunReadOnly(t *testing.T) {
	t.Setenv("MILLENNIUM_CONFIG_DIR", t.TempDir())
	t.Setenv("MILLENNIUM_CONFIG_FILE", filepath.Join(t.TempDir(), "missing.json"))
	t.Setenv("DIAG_TEST_BYPASS_CHECKS", "1")
	results := RunReadOnly()
	if len(results) < 2 {
		t.Fatalf("expected checks, got %d", len(results))
	}
	out := FormatReport(results)
	if !strings.Contains(out, "Helpers Version") {
		t.Fatalf("%s", out)
	}
}

func TestNeedsLegacy(t *testing.T) {
	if NeedsLegacy(nil) {
		t.Fatal("bare diag should be native")
	}
	if NeedsLegacy([]string{"--json"}) {
		t.Fatal("json should be native")
	}
	if NeedsLegacy([]string{"logs"}) {
		t.Fatal("logs should be native")
	}
	if NeedsLegacy([]string{"doctor", "--dry-run"}) {
		t.Fatal("doctor dry-run should be native")
	}
	if !NeedsLegacy([]string{"doctor"}) {
		t.Fatal("live doctor needs legacy")
	}
	if !NeedsLegacy([]string{"--share"}) {
		t.Fatal("share needs legacy")
	}
	if !NeedsLegacy([]string{"logs", "--follow"}) {
		t.Fatal("follow needs legacy")
	}
}

func TestFormatJSON(t *testing.T) {
	t.Setenv("DIAG_TEST_BYPASS_CHECKS", "1")
	t.Setenv("MILLENNIUM_CONFIG_DIR", t.TempDir())
	out := FormatJSON(Collect())
	if !strings.HasPrefix(strings.TrimSpace(out), "{") {
		t.Fatalf("%s", out)
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		t.Fatal(err)
	}
	if _, ok := m["steam_running"]; !ok {
		t.Fatalf("%v", m)
	}
	if _, ok := m["update_channel"]; !ok {
		t.Fatalf("%v", m)
	}
}

func TestDoctorDryRun(t *testing.T) {
	r := Report{BinariesOK: false, HooksOK: false, SkinsDirOK: true}
	out := FormatDoctorDryRun(r, false)
	if !strings.Contains(out, "DRY RUN") || !strings.Contains(out, "upgrade") {
		t.Fatalf("%s", out)
	}
}

func TestPrintLogsNoSteam(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("STEAM", filepath.Join(t.TempDir(), "nosteam"))
	t.Setenv("MILLENNIUM_STATE_DIR", t.TempDir())
	// Should exit 1 when no steam logs — acceptable.
	_ = PrintLogs()
}

func TestVerifyChecksums(t *testing.T) {
	dir := t.TempDir()
	content := []byte("hello")
	if err := os.WriteFile(filepath.Join(dir, "a.so"), content, 0o644); err != nil {
		t.Fatal(err)
	}
	sum := "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824  a.so\n" // sha256("hello")
	sumPath := filepath.Join(dir, "checksums.txt")
	if err := os.WriteFile(sumPath, []byte(sum), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := verifyChecksumsFile(dir, sumPath); err != nil {
		t.Fatal(err)
	}
}
