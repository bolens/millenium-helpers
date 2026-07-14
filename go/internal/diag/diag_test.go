package diag

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
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
	if NeedsLegacy([]string{"--share"}) {
		t.Fatal("share should be native")
	}
	if NeedsLegacy([]string{"logs"}) {
		t.Fatal("logs should be native")
	}
	if NeedsLegacy([]string{"doctor", "--dry-run"}) {
		t.Fatal("doctor dry-run should be native")
	}
	if NeedsLegacy([]string{"doctor"}) {
		t.Fatal("live doctor should be native")
	}
	if !NeedsLegacy([]string{"logs", "--follow"}) {
		t.Fatal("follow needs legacy")
	}
}

func TestDoctorPlan(t *testing.T) {
	r := Report{
		BinariesOK: false, HooksOK: false, SkinsDirOK: false,
		FlatpakOK: true, TimerActive: true, SudoersOK: true,
		LingerOK: true, PermissionsOK: true, TaskScheduled: true,
	}
	steps := DoctorPlan(r, false)
	ids := map[string]bool{}
	for _, s := range steps {
		ids[s.ID] = true
	}
	if !ids["upgrade_force"] || !ids["skins_dir"] {
		t.Fatalf("%#v", steps)
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
	_ = PrintLogs()
}

func TestRedactAndUpload(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("USER", "alice")
	t.Setenv("GITHUB_TOKEN", "ghp_secrettokenvalue1234567890abcd")
	body := home + "/.config has ghp_secrettokenvalue1234567890abcd for alice"
	got := RedactReport(body)
	if strings.Contains(got, home) || strings.Contains(got, "alice") || strings.Contains(got, "ghp_secret") {
		t.Fatalf("not redacted: %s", got)
	}
	if !strings.Contains(got, "[REDACTED]") || !strings.Contains(got, "~") {
		t.Fatalf("%s", got)
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("method %s", r.Method)
		}
		_, _ = w.Write([]byte("https://paste.rs/abc123"))
	}))
	t.Cleanup(srv.Close)
	prev := pasteEndpoint
	prevDo := httpDo
	t.Cleanup(func() {
		pasteEndpoint = prev
		httpDo = prevDo
	})
	pasteEndpoint = srv.URL
	httpDo = srv.Client().Do

	url, err := UploadPasteRS("hello")
	if err != nil || url != "https://paste.rs/abc123" {
		t.Fatalf("%s %v", url, err)
	}
}

func TestVerifyChecksums(t *testing.T) {
	dir := t.TempDir()
	content := []byte("hello")
	if err := os.WriteFile(filepath.Join(dir, "a.so"), content, 0o644); err != nil {
		t.Fatal(err)
	}
	sum := "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824  a.so\n"
	sumPath := filepath.Join(dir, "checksums.txt")
	if err := os.WriteFile(sumPath, []byte(sum), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := verifyChecksumsFile(dir, sumPath); err != nil {
		t.Fatal(err)
	}
}
