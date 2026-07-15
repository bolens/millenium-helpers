package install

import (
	"os"
	"path/filepath"
	"runtime"
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

func TestInstallUninstallFixture(t *testing.T) {
	root := repoRoot(t)
	binName := "millennium"
	if runtime.GOOS == "windows" {
		binName = "millennium.exe"
	}
	srcBin := filepath.Join(root, "bin", binName)
	if _, err := os.Stat(srcBin); err != nil {
		t.Skip("bin/millennium missing; run make build")
	}

	prefix := t.TempDir()
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
	o := Options{
		Action:        "install",
		Track:         "checkout",
		TargetDir:     target,
		LibDir:        lib,
		InstallRoot:   prefix,
		SourceRoot:    root,
		DispatcherSrc: srcBin,
		SkipWizard:    true,
	}
	res, err := Run(o)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Plan) == 0 {
		t.Fatal("empty plan")
	}
	if _, err := os.Stat(filepath.Join(target, binName)); err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS != "windows" {
		if _, err := os.Stat(filepath.Join(target, "millennium-upgrade")); err != nil {
			t.Fatal("missing twin:", err)
		}
		if _, err := os.Stat(filepath.Join(lib, "common.sh")); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(filepath.Join(lib, "install-meta.json")); err != nil {
			t.Fatal(err)
		}
	} else {
		if _, err := os.Stat(filepath.Join(target, "millennium-upgrade.cmd")); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(filepath.Join(prefix, "install-meta.json")); err != nil {
			t.Fatal(err)
		}
	}

	o.Action = "uninstall"
	if _, err := Run(o); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(target, binName)); !os.IsNotExist(err) {
		t.Fatalf("binary still present: %v", err)
	}
}

func TestInstallDryRunNoWrites(t *testing.T) {
	root := repoRoot(t)
	binName := "millennium"
	if runtime.GOOS == "windows" {
		binName = "millennium.exe"
	}
	srcBin := filepath.Join(root, "bin", binName)
	if _, err := os.Stat(srcBin); err != nil {
		t.Skip("bin/millennium missing; run make build")
	}
	prefix := t.TempDir()
	o := Options{
		Action:        "install",
		DryRun:        true,
		Track:         "checkout",
		TargetDir:     filepath.Join(prefix, "bin"),
		LibDir:        filepath.Join(prefix, "lib"),
		InstallRoot:   prefix,
		SourceRoot:    root,
		DispatcherSrc: srcBin,
		SkipWizard:    true,
	}
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
