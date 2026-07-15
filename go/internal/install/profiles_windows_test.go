//go:build windows

package install

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWindowsCompletionHooksInstallAndRemove(t *testing.T) {
	root := repoRoot(t)
	srcBin := stubDispatcher(t)
	prefix := t.TempDir()
	t.Setenv("USERPROFILE", prefix)
	t.Setenv("PSTESTS", "true")

	o := Options{
		Action:        "install",
		Track:         "checkout",
		TargetDir:     filepath.Join(prefix, ".millennium-helpers", "bin"),
		InstallRoot:   filepath.Join(prefix, ".millennium-helpers"),
		SourceRoot:    root,
		DispatcherSrc: srcBin,
		SkipWizard:    true,
	}
	if _, err := Run(o); err != nil {
		t.Fatal(err)
	}

	profile := filepath.Join(prefix, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1")
	body, err := os.ReadFile(profile)
	if err != nil {
		t.Fatal("profile hook not written:", err)
	}
	if !strings.Contains(string(body), "millennium-helpers.completion.ps1") {
		t.Fatalf("profile missing completion hook: %s", body)
	}
	legacy := filepath.Join(prefix, "Documents", "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1")
	if b, err := os.ReadFile(legacy); err != nil || !strings.Contains(string(b), "millennium-helpers.completion.ps1") {
		t.Fatalf("WindowsPowerShell profile hook missing: %v %s", err, b)
	}

	o.Action = "uninstall"
	if _, err := Run(o); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{profile, legacy} {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		if strings.Contains(string(b), "millennium-helpers.completion.ps1") {
			t.Fatalf("hook still present in %s", p)
		}
	}
}
