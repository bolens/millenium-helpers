//go:build windows

package upgrade

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolveWindowsBackupContentsNested(t *testing.T) {
	root := t.TempDir()
	mill := filepath.Join(root, "millennium")
	_ = os.MkdirAll(mill, 0o755)
	_ = os.WriteFile(filepath.Join(mill, "version.txt"), []byte("1\n"), 0o644)
	_ = os.WriteFile(filepath.Join(root, "wsock32.dll"), []byte("dll"), 0o644)
	m, w, err := resolveWindowsBackupContents(root)
	if err != nil || m != mill || w == "" {
		t.Fatalf("m=%s w=%s err=%v", m, w, err)
	}
}

func TestResolveWindowsBackupContentsFlat(t *testing.T) {
	root := t.TempDir()
	_ = os.WriteFile(filepath.Join(root, "version.txt"), []byte("1\n"), 0o644)
	m, w, err := resolveWindowsBackupContents(root)
	if err != nil || m != root || w != "" {
		t.Fatalf("m=%s w=%s err=%v", m, w, err)
	}
}

func TestSwapWindowsRollbackActivatesStagedInstall(t *testing.T) {
	steam := t.TempDir()
	active := filepath.Join(steam, "millennium")
	staged := filepath.Join(steam, "staged", "millennium")
	_ = os.MkdirAll(active, 0o755)
	_ = os.MkdirAll(staged, 0o755)
	_ = os.WriteFile(filepath.Join(active, "marker"), []byte("current"), 0o644)
	_ = os.WriteFile(filepath.Join(staged, "marker"), []byte("backup"), 0o644)
	if err := swapWindowsRollback(steam, staged, ""); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(active, "marker"))
	if err != nil || string(got) != "backup" {
		t.Fatalf("marker=%q err=%v", got, err)
	}
}

func TestSwapWindowsRollbackRestoresCurrentOnActivationFailure(t *testing.T) {
	steam := t.TempDir()
	active := filepath.Join(steam, "millennium")
	staged := filepath.Join(steam, "staged", "millennium")
	_ = os.MkdirAll(active, 0o755)
	_ = os.MkdirAll(staged, 0o755)
	_ = os.WriteFile(filepath.Join(active, "marker"), []byte("current"), 0o644)
	_ = os.WriteFile(filepath.Join(staged, "marker"), []byte("backup"), 0o644)
	if err := swapWindowsRollback(steam, staged, filepath.Join(steam, "missing-wsock32.dll")); err == nil {
		t.Fatal("expected activation failure")
	}
	got, err := os.ReadFile(filepath.Join(active, "marker"))
	if err != nil || string(got) != "current" {
		t.Fatalf("marker=%q err=%v", got, err)
	}
}
