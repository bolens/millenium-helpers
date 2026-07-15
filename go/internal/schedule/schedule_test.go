package schedule

import (
	"os"
	"path/filepath"
	"runtime"
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

func TestParseSystemdScopeFlags(t *testing.T) {
	if runtime.GOOS != "linux" {
		_, err := ParseArgs([]string{"enable", "--system"})
		if err == nil {
			t.Fatal("expected --system reject off linux")
		}
		return
	}
	o, err := ParseArgs([]string{"enable", "--system", "stable"})
	if err != nil || o.SystemdScope != ScopeSystem || o.Channel != "stable" {
		t.Fatalf("%+v err=%v", o, err)
	}
	o, err = ParseArgs([]string{"enable", "--user"})
	if err != nil || o.SystemdScope != ScopeUser {
		t.Fatalf("%+v err=%v", o, err)
	}
	_, err = ParseArgs([]string{"enable", "--system", "--user"})
	if err == nil {
		t.Fatal("expected conflict")
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
	if NeedsLegacy(Options{Action: "setup"}) {
		t.Fatal("setup should be native")
	}
	if NeedsLegacy(Options{Action: "status"}) {
		t.Fatal("status should be native")
	}
	if NeedsLegacy(Options{Action: "enable", DryRun: true}) {
		t.Fatal("dry-run enable should be native")
	}
	if NeedsLegacy(Options{Action: "enable"}) {
		t.Fatal("enable should be native (Unix timers / Windows Task Scheduler)")
	}
	if NeedsLegacy(Options{Action: "disable"}) {
		t.Fatal("disable should be native")
	}
}

func TestBuildEnablePowerShell(t *testing.T) {
	arg, script := buildEnablePowerShell(
		"beta",
		`C:\Users\alice\AppData\Local\millennium-helpers`,
		`C:\helpers\millennium.exe`,
		`C:\helpers\millennium.exe`,
		`C:\helpers\updater.log`,
		15,
	)
	if !strings.Contains(arg, "millennium.exe") || !strings.Contains(arg, "upgrade") || !strings.Contains(arg, "beta") {
		t.Fatalf("taskArg=%s", arg)
	}
	if !strings.Contains(arg, "theme update") {
		t.Fatalf("missing theme update: %s", arg)
	}
	if !strings.Contains(script, "Register-ScheduledTask") || !strings.Contains(script, WinTaskName) {
		t.Fatalf("script=%s", script)
	}
	if !strings.Contains(script, "Minutes 15") {
		t.Fatalf("missing delay: %s", script)
	}
	// Single-quote escaping in taskArg (Register script re-escapes via psSingle)
	arg2, _ := buildEnablePowerShell("stable", `C:\O'Brien`, "u.exe", "u.exe", "l.log", 0)
	if !strings.Contains(arg2, `O''Brien`) {
		t.Fatalf("escape failed: %s", arg2)
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
