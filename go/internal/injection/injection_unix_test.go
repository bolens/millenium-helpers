//go:build unix && !darwin

package injection

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDisableEnablePreservesBootstrapAndConfig(t *testing.T) {
	home := t.TempDir()
	libBase := t.TempDir()
	steam := filepath.Join(home, ".local", "share", "Steam")
	config := filepath.Join(home, ".config", "millennium", "config.json")
	if err := os.MkdirAll(filepath.Dir(config), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(config, []byte(`{"plugins":{"enabled":true}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, arch := range []struct{ dir, lib string }{{"ubuntu12_32", "x86"}, {"ubuntu12_64", "hhx64"}} {
		target := filepath.Join(libBase, "millennium", "libmillennium_bootstrap_"+arch.lib+".so")
		hook := filepath.Join(steam, arch.dir, "libXtst.so.6")
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(target, []byte("bootstrap"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.MkdirAll(filepath.Dir(hook), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink(target, hook); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("HOME", home)
	t.Setenv("MOCK_LIB_DIR", libBase)

	if _, err := platformSetEnabled(false, false); err != nil {
		t.Fatal(err)
	}
	state, _, err := platformStatus()
	if err != nil || state != "disabled" {
		t.Fatalf("status after disable = %q, %v", state, err)
	}
	if got, err := os.ReadFile(config); err != nil || string(got) != `{"plugins":{"enabled":true}}` {
		t.Fatalf("config changed: %q, %v", got, err)
	}
	if _, err := platformSetEnabled(true, false); err != nil {
		t.Fatal(err)
	}
	state, _, err = platformStatus()
	if err != nil || state != "enabled" {
		t.Fatalf("status after enable = %q, %v", state, err)
	}
}

func TestDisableRefusesForeignHook(t *testing.T) {
	home := t.TempDir()
	steam := filepath.Join(home, ".local", "share", "Steam")
	hook := filepath.Join(steam, "ubuntu12_32", "libXtst.so.6")
	if err := os.MkdirAll(filepath.Dir(hook), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(hook, []byte("not millennium"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("MOCK_LIB_DIR", t.TempDir())
	if _, err := platformSetEnabled(false, false); err == nil {
		t.Fatal("expected foreign hook refusal")
	}
}
