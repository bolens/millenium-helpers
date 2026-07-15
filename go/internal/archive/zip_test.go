package archive

import (
	"archive/zip"
	"os"
	"path/filepath"
	"testing"
)

func TestSafeExtractZipRejectsSlip(t *testing.T) {
	dir := t.TempDir()
	zipPath := filepath.Join(dir, "bad.zip")
	f, err := os.Create(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(f)
	w, err := zw.Create("../evil.txt")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = w.Write([]byte("nope"))
	_ = zw.Close()
	_ = f.Close()
	dest := filepath.Join(dir, "out")
	if err := SafeExtractZip(zipPath, dest); err == nil {
		t.Fatal("expected zip-slip rejection")
	}
}

func TestSafeExtractZipAcceptsSafe(t *testing.T) {
	dir := t.TempDir()
	zipPath := filepath.Join(dir, "good.zip")
	f, err := os.Create(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(f)
	w, err := zw.Create("Theme/skin.json")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = w.Write([]byte(`{}`))
	_ = zw.Close()
	_ = f.Close()
	dest := filepath.Join(dir, "out")
	if err := SafeExtractZip(zipPath, dest); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dest, "Theme", "skin.json")); err != nil {
		t.Fatal(err)
	}
}
