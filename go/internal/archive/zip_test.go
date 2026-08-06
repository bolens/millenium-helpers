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

func TestSafeExtractZipRejectsLimits(t *testing.T) {
	tests := []struct {
		name   string
		files  map[string]string
		limits extractionLimits
	}{
		{
			name:   "file size",
			files:  map[string]string{"large": "12345"},
			limits: extractionLimits{maxEntries: 10, maxFileBytes: 4, maxTotalBytes: 10},
		},
		{
			name:   "total size",
			files:  map[string]string{"one": "123", "two": "456"},
			limits: extractionLimits{maxEntries: 10, maxFileBytes: 4, maxTotalBytes: 5},
		},
		{
			name:   "entry count",
			files:  map[string]string{"one": "1", "two": "2"},
			limits: extractionLimits{maxEntries: 1, maxFileBytes: 4, maxTotalBytes: 5},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			zipPath := filepath.Join(dir, "limited.zip")
			writeTestZip(t, zipPath, tt.files)
			if err := safeExtractZip(zipPath, filepath.Join(dir, "out"), tt.limits); err == nil {
				t.Fatal("expected extraction limit error")
			}
		})
	}
}

func writeTestZip(t *testing.T, zipPath string, files map[string]string) {
	t.Helper()
	f, err := os.Create(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(f)
	for name, text := range files {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(text)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
}
