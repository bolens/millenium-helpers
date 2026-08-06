package archive

import (
	"archive/tar"
	"compress/gzip"
	"os"
	"path/filepath"
	"testing"
)

func TestSafeExtractTarGzRejectsSlip(t *testing.T) {
	dir := t.TempDir()
	archivePath := filepath.Join(dir, "bad.tar.gz")
	f, err := os.Create(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	body := []byte("nope")
	hdr := &tar.Header{
		Name:     "../evil.txt",
		Mode:     0o644,
		Size:     int64(len(body)),
		Typeflag: tar.TypeReg,
	}
	if err := tw.WriteHeader(hdr); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write(body); err != nil {
		t.Fatal(err)
	}
	_ = tw.Close()
	_ = gz.Close()
	_ = f.Close()

	dest := filepath.Join(dir, "out")
	if err := SafeExtractTarGz(archivePath, dest); err == nil {
		t.Fatal("expected tar-slip rejection")
	}
}

func TestSafeExtractTarGzAcceptsSafe(t *testing.T) {
	dir := t.TempDir()
	archivePath := filepath.Join(dir, "good.tar.gz")
	f, err := os.Create(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	body := []byte("ok")
	hdr := &tar.Header{
		Name:     "usr/lib/millennium/VERSION",
		Mode:     0o644,
		Size:     int64(len(body)),
		Typeflag: tar.TypeReg,
	}
	if err := tw.WriteHeader(hdr); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write(body); err != nil {
		t.Fatal(err)
	}
	_ = tw.Close()
	_ = gz.Close()
	_ = f.Close()

	dest := filepath.Join(dir, "out")
	if err := SafeExtractTarGz(archivePath, dest); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dest, "usr", "lib", "millennium", "VERSION")); err != nil {
		t.Fatal(err)
	}
}

func TestSafeExtractTarGzRejectsLimits(t *testing.T) {
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
			archivePath := filepath.Join(dir, "limited.tar.gz")
			writeTestTarGz(t, archivePath, tt.files)
			if err := safeExtractTarGz(archivePath, filepath.Join(dir, "out"), tt.limits); err == nil {
				t.Fatal("expected extraction limit error")
			}
		})
	}
}

func writeTestTarGz(t *testing.T, archivePath string, files map[string]string) {
	t.Helper()
	f, err := os.Create(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	for name, text := range files {
		body := []byte(text)
		if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o644, Size: int64(len(body)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write(body); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
}
