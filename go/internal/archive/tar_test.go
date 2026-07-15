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
