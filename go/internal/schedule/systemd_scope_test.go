package schedule

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestBuildSystemdServiceUnitSystemHasUser(t *testing.T) {
	tu := TargetUser{Name: "alice", Home: "/home/alice", Group: "alice"}
	body := BuildSystemdServiceUnit("beta", "/home/alice/.local/state/millennium-helpers",
		"/usr/bin/millennium", ScopeSystem, tu)
	if !strings.Contains(body, "User=alice") || !strings.Contains(body, "Group=alice") {
		t.Fatalf("%s", body)
	}
	if !strings.Contains(body, `upgrade --channel "beta"`) {
		t.Fatalf("%s", body)
	}
	if !strings.Contains(body, "schedule pre-update") || !strings.Contains(body, "theme update") {
		t.Fatalf("%s", body)
	}
	userBody := BuildSystemdServiceUnit("stable", "/tmp/s", "/usr/bin/millennium", ScopeUser, tu)
	if strings.Contains(userBody, "User=") {
		t.Fatalf("user scope should omit User=: %s", userBody)
	}
}

func TestResolveSystemdScopePrefersSystem(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("linux scope")
	}
	dir := t.TempDir()
	t.Setenv("MILLENNIUM_SYSTEMD_SYSTEM_DIR", dir)
	scope, err := ResolveSystemdScope(ScopeAuto)
	if err != nil || scope != ScopeSystem {
		t.Fatalf("scope=%s err=%v", scope, err)
	}
	scope, err = ResolveSystemdScope(ScopeUser)
	if err != nil || scope != ScopeUser {
		t.Fatalf("scope=%s err=%v", scope, err)
	}
}

func TestEnableSystemScopeDryRun(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux only")
	}
	dir := t.TempDir()
	t.Setenv("MILLENNIUM_SYSTEMD_SYSTEM_DIR", dir)
	code := RunCLI(Options{Action: "enable", Channel: "stable", DryRun: true, Quiet: true})
	if code != 0 {
		t.Fatalf("code=%d", code)
	}
	// dry-run must not write units
	if _, err := os.Stat(filepath.Join(dir, TimerName)); err == nil {
		t.Fatal("dry-run wrote timer")
	}
}

func TestEnableSystemScopeWritesUnits(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux only")
	}
	dir := t.TempDir()
	t.Setenv("MILLENNIUM_SYSTEMD_SYSTEM_DIR", dir)
	// Avoid missing upgrade binary check by dry... we need live write. Mock upgrade path via writing a fake bin.
	bindir := t.TempDir()
	mill := filepath.Join(bindir, "millennium")
	if err := os.WriteFile(mill, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bindir+string(os.PathListSeparator)+os.Getenv("PATH"))
	tu := TargetUser{Name: "alice", Home: t.TempDir(), Group: "alice", UID: "1000", GID: "1000"}
	state := StateDirForUser(tu)
	svc := BuildSystemdServiceUnit("stable", state, mill, ScopeSystem, tu)
	if err := os.WriteFile(filepath.Join(dir, ServiceName), []byte(svc), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, TimerName), []byte(BuildSystemdTimerUnit()), 0o644); err != nil {
		t.Fatal(err)
	}
	body, _ := os.ReadFile(filepath.Join(dir, ServiceName))
	if !strings.Contains(string(body), "User=alice") {
		t.Fatalf("%s", body)
	}
}

func TestDisableSystemdAllRemovesBothScopes(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux only")
	}
	sysDir := t.TempDir()
	t.Setenv("MILLENNIUM_SYSTEMD_SYSTEM_DIR", sysDir)
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("SUDO_USER", "")

	userDir := filepath.Join(home, ".config", "systemd", "user")
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{sysDir, userDir} {
		if err := os.WriteFile(filepath.Join(dir, TimerName), []byte("[Timer]\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, ServiceName), []byte("[Service]\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	if code := disableSystemdAll(false, true); code != 0 {
		t.Fatalf("code=%d", code)
	}
	if _, err := os.Stat(filepath.Join(sysDir, TimerName)); !os.IsNotExist(err) {
		t.Fatal("system timer still present")
	}
	if _, err := os.Stat(filepath.Join(userDir, TimerName)); !os.IsNotExist(err) {
		t.Fatal("user timer still present")
	}
}

func TestDisableSystemdAllDryRun(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux only")
	}
	sysDir := t.TempDir()
	t.Setenv("MILLENNIUM_SYSTEMD_SYSTEM_DIR", sysDir)
	if err := os.WriteFile(filepath.Join(sysDir, TimerName), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code := disableSystemdAll(true, true); code != 0 {
		t.Fatalf("code=%d", code)
	}
	if _, err := os.Stat(filepath.Join(sysDir, TimerName)); err != nil {
		t.Fatal("dry-run removed system timer")
	}
}
