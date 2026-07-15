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
