package schedule

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseArgs(t *testing.T) {
	o, err := ParseArgs([]string{"enable", "beta", "--dry-run"})
	if err != nil || o.Action != "enable" || o.Channel != "beta" || !o.DryRun {
		t.Fatalf("%+v err=%v", o, err)
	}
	o, err = ParseArgs([]string{"status"})
	if err != nil || o.Action != "status" {
		t.Fatalf("%+v err=%v", o, err)
	}
	_, err = ParseArgs([]string{"--nope"})
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestFormatStatusDisabled(t *testing.T) {
	out := FormatStatus(Status{Configured: false, Channel: "stable"})
	if !strings.Contains(out, "Scheduler disabled") {
		t.Fatalf("%s", out)
	}
}

func TestFormatStatusConfigured(t *testing.T) {
	home := t.TempDir()
	t.Setenv("MILLENNIUM_STATE_DIR", filepath.Join(home, "state"))
	st := Status{
		Configured: true,
		Channel:    "beta",
		Lines:      []string{"=== Timer ===", "present"},
	}
	out := FormatStatus(st)
	if !strings.Contains(out, "Channel     : beta") || !strings.Contains(out, "Disable") {
		t.Fatalf("%s", out)
	}
}

func TestNeedsLegacy(t *testing.T) {
	if !NeedsLegacy(Options{Action: "setup"}) {
		t.Fatal("setup should be legacy")
	}
	if NeedsLegacy(Options{Action: "status"}) {
		t.Fatal("status should be native")
	}
	if NeedsLegacy(Options{Action: "enable", DryRun: true}) {
		t.Fatal("dry-run enable should be native")
	}
}

func TestResolveChannelFromConfig(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("MILLENNIUM_CONFIG_DIR", dir)
	if err := os.WriteFile(filepath.Join(dir, "config.json"), []byte(`{"update_channel":"main"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := ResolveChannel(""); got != "main" {
		t.Fatalf("got %s", got)
	}
	if got := ResolveChannel("beta"); got != "beta" {
		t.Fatalf("got %s", got)
	}
}

func TestRunCLIEnableDryRunCron(t *testing.T) {
	code := RunCLI(Options{Action: "enable", Channel: "stable", Cron: true, DryRun: true})
	if code != 0 {
		t.Fatalf("code=%d", code)
	}
}

func TestChannelFromServiceFile(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "svc")
	body := `ExecStart=/bin/bash -c '... --channel beta --quiet ...'`
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := channelFromServiceFile(p); got != "beta" {
		t.Fatalf("got %s", got)
	}
}
