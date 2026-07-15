package install

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	// go/internal/install → repo root
	root := filepath.Clean(filepath.Join(wd, "..", "..", ".."))
	if _, err := os.Stat(filepath.Join(root, "VERSION")); err != nil {
		t.Skip("not running inside checkout")
	}
	return root
}

// stubDispatcher writes a placeholder binary for copy-based install fixtures.
// Install only copies this file onto PATH; it need not be a real millennium build.
func stubDispatcher(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	name := "millennium"
	body := []byte("#!/bin/sh\necho millenium-stub\n")
	if runtime.GOOS == "windows" {
		name = "millennium.exe"
		body = []byte("MZ-stub")
	}
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, body, 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func fixtureOptions(t *testing.T, root, prefix, srcBin string) Options {
	t.Helper()
	target := filepath.Join(prefix, "bin")
	lib := filepath.Join(prefix, "lib")
	t.Setenv("MILLENNIUM_BASH_COMPLETION_DIR", filepath.Join(prefix, "bash"))
	t.Setenv("MILLENNIUM_ZSH_COMPLETION_DIR", filepath.Join(prefix, "zsh"))
	t.Setenv("MILLENNIUM_FISH_COMPLETION_DIR", filepath.Join(prefix, "fish"))
	t.Setenv("MILLENNIUM_NUSHELL_COMPLETION_DIR", filepath.Join(prefix, "nu"))
	t.Setenv("MILLENNIUM_MAN_DIR", filepath.Join(prefix, "man"))
	if runtime.GOOS == "linux" {
		t.Setenv("MOCK_SUDOERS_FILE", filepath.Join(prefix, "sudoers.d", "millennium-helpers"))
		t.Setenv("SUDO_USER", "testuser")
	}
	if runtime.GOOS == "windows" {
		// Avoid mutating the real User PATH in unit tests.
		t.Setenv("PSTESTS", "true")
		t.Setenv("USERPROFILE", prefix)
	}
	return Options{
		Action:        "install",
		Track:         "checkout",
		TargetDir:     target,
		LibDir:        lib,
		InstallRoot:   prefix,
		SourceRoot:    root,
		DispatcherSrc: srcBin,
		SkipWizard:    true,
	}
}

func TestInstallUninstallFixture(t *testing.T) {
	root := repoRoot(t)
	srcBin := stubDispatcher(t)
	binName := filepath.Base(srcBin)

	prefix := t.TempDir()
	o := fixtureOptions(t, root, prefix, srcBin)
	res, err := Run(o)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Plan) == 0 {
		t.Fatal("empty plan")
	}
	if _, err := os.Stat(filepath.Join(o.TargetDir, binName)); err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS != "windows" {
		if _, err := os.Stat(filepath.Join(o.TargetDir, "millennium-upgrade")); !os.IsNotExist(err) {
			t.Fatal("PATH twin should not be installed:", filepath.Join(o.TargetDir, "millennium-upgrade"))
		}
		if _, err := os.Stat(filepath.Join(o.LibDir, "VERSION")); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(filepath.Join(o.LibDir, "install-meta.json")); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(filepath.Join(prefix, "bash", "millennium-helpers")); err != nil {
			t.Fatal("bash completions missing:", err)
		}
		if _, err := os.Stat(filepath.Join(prefix, "fish", "millennium.fish")); err != nil {
			t.Fatal("fish completions missing:", err)
		}
		if _, err := os.Stat(filepath.Join(prefix, "man", "millennium.1")); err != nil {
			t.Fatal("man page missing:", err)
		}
	} else {
		if _, err := os.Stat(filepath.Join(o.TargetDir, "millennium-upgrade.cmd")); !os.IsNotExist(err) {
			t.Fatal("PATH twin should not be installed")
		}
		if _, err := os.Stat(filepath.Join(prefix, "install-meta.json")); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(filepath.Join(o.TargetDir, "millennium-helpers.completion.ps1")); err != nil {
			t.Fatal("powershell completions missing:", err)
		}
	}

	if runtime.GOOS == "linux" {
		sudoersPath := filepath.Join(prefix, "sudoers.d", "millennium-helpers")
		body, err := os.ReadFile(sudoersPath)
		if err != nil {
			t.Fatal("sudoers not written:", err)
		}
		text := string(body)
		want := SudoersLine("testuser", o.TargetDir)
		if text != want {
			t.Fatalf("sudoers mismatch\nwant %q\ngot  %q", want, text)
		}
		for _, twin := range []string{"millennium-upgrade", "millennium-diag", "millennium-repair", "millennium-purge"} {
			if strings.Contains(text, twin) {
				t.Fatalf("sudoers still allowlists twin %q: %s", twin, text)
			}
		}
	}

	o.Action = "uninstall"
	if _, err := Run(o); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(o.TargetDir, binName)); !os.IsNotExist(err) {
		t.Fatalf("binary still present: %v", err)
	}
	if runtime.GOOS == "linux" {
		if _, err := os.Stat(filepath.Join(prefix, "sudoers.d", "millennium-helpers")); !os.IsNotExist(err) {
			t.Fatal("sudoers still present after uninstall")
		}
	}
}

func TestInstallDryRunNoWrites(t *testing.T) {
	root := repoRoot(t)
	srcBin := stubDispatcher(t)
	prefix := t.TempDir()
	o := fixtureOptions(t, root, prefix, srcBin)
	o.DryRun = true
	res, err := Run(o)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Plan) < 2 || res.Plan[0] != "DRY RUN MODE: No changes will be made" {
		t.Fatalf("%v", res.Plan)
	}
	entries, _ := os.ReadDir(prefix)
	if len(entries) != 0 {
		t.Fatalf("dry-run wrote files: %v", entries)
	}
}
