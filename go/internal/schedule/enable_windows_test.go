//go:build windows

package schedule

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunEnableDisableWindows(t *testing.T) {
	dir := t.TempDir()
	exe := filepath.Join(dir, "millennium.exe")
	if err := os.WriteFile(exe, []byte("MZ"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("MILLENNIUM_SCRIPTS_DIR", dir)

	var scripts []string
	windowsAdminCheck = func() bool { return true }
	windowsPowerShell = func(script string) (string, error) {
		scripts = append(scripts, script)
		if strings.Contains(script, "Unregister-ScheduledTask") {
			return "removed\n", nil
		}
		return "", nil
	}
	t.Cleanup(func() {
		windowsAdminCheck = isWindowsAdmin
		windowsPowerShell = runPowerShell
	})

	if code := runEnable("stable", false, false, true, ScopeAuto); code != 0 {
		t.Fatalf("enable code=%d", code)
	}
	if len(scripts) != 1 || !strings.Contains(scripts[0], "Register-ScheduledTask") {
		t.Fatalf("scripts=%v", scripts)
	}
	if !strings.Contains(scripts[0], "upgrade --channel") {
		t.Fatalf("expected Go upgrade invoke, got: %s", scripts[0])
	}
	scripts = nil
	if code := runDisable(false, true); code != 0 {
		t.Fatalf("disable code=%d", code)
	}
	if len(scripts) != 1 || !strings.Contains(scripts[0], "Unregister-ScheduledTask") {
		t.Fatalf("scripts=%v", scripts)
	}
}

func TestRunEnableRequiresAdmin(t *testing.T) {
	windowsAdminCheck = func() bool { return false }
	t.Cleanup(func() { windowsAdminCheck = isWindowsAdmin })
	if code := runEnable("stable", false, false, true, ScopeAuto); code != 1 {
		t.Fatalf("code=%d", code)
	}
}
