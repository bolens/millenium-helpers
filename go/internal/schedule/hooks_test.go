package schedule

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestNeedsLegacyHooksNative(t *testing.T) {
	if NeedsLegacy(Options{Action: "pre-update"}) {
		t.Fatal("pre-update should be native")
	}
	if NeedsLegacy(Options{Action: "post-update"}) {
		t.Fatal("post-update should be native")
	}
	if NeedsLegacy(Options{Action: "setup"}) {
		t.Fatal("setup should be native")
	}
}

func TestPreUpdateSchedulerGate(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix hooks")
	}
	t.Setenv("MILLENNIUM_SCHEDULER", "")
	code := runPreUpdate()
	if code != 1 {
		t.Fatalf("code=%d", code)
	}
}

func TestPreUpdateSteamNotRunning(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix hooks")
	}
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("MILLENNIUM_STATE_DIR", filepath.Join(home, "state"))
	t.Setenv("MILLENNIUM_SCHEDULER", "1")
	t.Setenv("MOCK_PROC", filepath.Join(home, "empty-proc"))
	_ = os.MkdirAll(filepath.Join(home, "empty-proc"), 0o755)

	// Prefer that pgrep fails (no steam). Put a stub first on PATH.
	bin := t.TempDir()
	stub := filepath.Join(bin, "pgrep")
	if err := os.WriteFile(stub, []byte("#!/bin/sh\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	code := runPreUpdate()
	if code != 0 {
		t.Fatalf("code=%d", code)
	}
}

func TestPostUpdateNoState(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix hooks")
	}
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("MILLENNIUM_STATE_DIR", filepath.Join(home, "state"))
	t.Setenv("MILLENNIUM_SCHEDULER", "1")
	verifyDiag = func() error { return nil }
	t.Cleanup(func() { verifyDiag = defaultVerifyDiag })

	code := runPostUpdate()
	if code != 0 {
		t.Fatalf("code=%d", code)
	}
}

func TestPostUpdateDiagFail(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix hooks")
	}
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("MILLENNIUM_STATE_DIR", filepath.Join(home, "state"))
	t.Setenv("MILLENNIUM_SCHEDULER", "1")
	verifyDiag = func() error { return os.ErrPermission }
	t.Cleanup(func() { verifyDiag = defaultVerifyDiag })

	code := runPostUpdate()
	if code != 1 {
		t.Fatalf("code=%d", code)
	}
}

func TestPostUpdateRelaunchBypass(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix hooks")
	}
	home := t.TempDir()
	stateDir := filepath.Join(home, "state")
	t.Setenv("HOME", home)
	t.Setenv("MILLENNIUM_STATE_DIR", stateDir)
	t.Setenv("MILLENNIUM_SCHEDULER", "1")
	t.Setenv("TEST_SUITE_RUN", "1")
	verifyDiag = func() error { return nil }
	t.Cleanup(func() { verifyDiag = defaultVerifyDiag })

	_ = os.MkdirAll(stateDir, 0o700)
	state := filepath.Join(stateDir, "relaunch.env")
	body := "export DISPLAY=':1'\nexport STEAM_ARGS=''\nexport WAS_FLATPAK='false'\n"
	if err := os.WriteFile(state, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	code := runPostUpdate()
	if code != 0 {
		t.Fatalf("code=%d", code)
	}
	if _, err := os.Stat(state); !os.IsNotExist(err) {
		t.Fatal("expected relaunch.env consumed")
	}
}

func TestRotateLogs(t *testing.T) {
	dir := t.TempDir()
	log := filepath.Join(dir, "updater.log")
	big := strings.Repeat("x", 5*1024*1024+10)
	if err := os.WriteFile(log, []byte(big), 0o644); err != nil {
		t.Fatal(err)
	}
	rotateLogs(dir)
	b, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), "Log file rotated") {
		t.Fatalf("%q", b)
	}
	if _, err := os.Stat(log + ".1"); err != nil {
		t.Fatal(err)
	}
}
