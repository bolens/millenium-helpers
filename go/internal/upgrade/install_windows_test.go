//go:build windows

package upgrade

import (
	"archive/zip"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNativeInstallWindows(t *testing.T) {
	home := t.TempDir()
	steam := filepath.Join(home, "Steam")
	_ = os.MkdirAll(steam, 0o755)
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)
	t.Setenv("STEAM", steam)

	archive := filepath.Join(t.TempDir(), "millennium-win.zip")
	if err := writeTestZip(archive); err != nil {
		t.Fatal(err)
	}
	o := Options{Channel: "stable", Quiet: true, Yes: true}
	handled, code := TryNativeInstall(o, archive, "9.9.9")
	if !handled || code != 0 {
		t.Fatalf("handled=%v code=%d", handled, code)
	}
	ver, err := os.ReadFile(filepath.Join(steam, "millennium", "version.txt"))
	if err != nil || strings.TrimSpace(string(ver)) != "9.9.9" {
		t.Fatalf("version=%s err=%v", ver, err)
	}
	if _, err := os.Stat(filepath.Join(steam, "millennium", "marker")); err != nil {
		t.Fatal(err)
	}
}

func TestRestoreWindowsBackup(t *testing.T) {
	root := t.TempDir()
	steam := filepath.Join(root, "Steam")
	bak := filepath.Join(root, "backup")
	stage := filepath.Join(root, "stage")
	for _, dir := range []string{
		filepath.Join(steam, "millennium"),
		filepath.Join(bak, "millennium"),
		filepath.Join(stage, "millennium"),
	} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(steam, "millennium", "marker"), []byte("partial"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bak, "millennium", "marker"), []byte("original"), 0o644); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(stage)
	if err != nil {
		t.Fatal(err)
	}
	err = restoreWindowsBackup(steam, bak, entries, errors.New("install failed"))
	if err == nil || !strings.Contains(err.Error(), "previous installation restored") {
		t.Fatalf("unexpected error: %v", err)
	}
	body, err := os.ReadFile(filepath.Join(steam, "millennium", "marker"))
	if err != nil {
		t.Fatal(err)
	}
	if string(body) != "original" {
		t.Fatalf("got %q", body)
	}
}

func writeTestZip(path string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	zw := zip.NewWriter(f)
	add := func(name, body string) error {
		w, err := zw.Create(name)
		if err != nil {
			return err
		}
		_, err = w.Write([]byte(body))
		return err
	}
	if err := add("millennium/marker", "installed\n"); err != nil {
		return err
	}
	if err := add("wsock32.dll", "dll-stub\n"); err != nil {
		return err
	}
	return zw.Close()
}
