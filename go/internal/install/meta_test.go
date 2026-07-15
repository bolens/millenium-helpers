package install

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteReadMeta(t *testing.T) {
	root := t.TempDir()
	if err := WriteMeta(root, Meta{Track: "checkout", Ref: "abc123", Version: "2.7.0"}); err != nil {
		t.Fatal(err)
	}
	m, ok, err := ReadMeta(root)
	if err != nil || !ok {
		t.Fatalf("ok=%v err=%v", ok, err)
	}
	if m.Track != "checkout" || m.Ref != "abc123" || m.Version != "2.7.0" || m.InstalledAt == "" {
		t.Fatalf("%+v", m)
	}
}

func TestMigrateMetaIfNeeded(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "VERSION"), []byte("2.7.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := MigrateMetaIfNeeded(root, "manual", ""); err != nil {
		t.Fatal(err)
	}
	m, ok, err := ReadMeta(root)
	if err != nil || !ok || m.Track != "release" || m.MigratedFrom != "legacy" {
		t.Fatalf("%+v ok=%v err=%v", m, ok, err)
	}
	// second call is no-op
	if err := MigrateMetaIfNeeded(root, "checkout", ""); err != nil {
		t.Fatal(err)
	}
	m2, _, _ := ReadMeta(root)
	if m2.Track != "release" {
		t.Fatalf("should not overwrite: %+v", m2)
	}
}
