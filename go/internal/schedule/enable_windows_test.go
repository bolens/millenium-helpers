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
	upgrade := filepath.Join(dir, "millennium-upgrade.ps1")
	theme := filepath.Join(dir, "millennium-theme.ps1")
	if err := os.WriteFile(upgrade, []byte("#"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(theme, []byte("#"), 0o644); err != nil {
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
