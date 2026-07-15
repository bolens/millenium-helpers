package install

import (
	"archive/tar"
	"compress/gzip"
	"os"
	"path/filepath"
	"testing"
)

func TestExtractTarGzAndFindRoot(t *testing.T) {
	dir := t.TempDir()
	archivePath := filepath.Join(dir, "helpers.tar.gz")
	f, err := os.Create(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	files := map[string]string{
		"millenium-helpers-2.7.0/VERSION":            "2.7.0\n",
		"millenium-helpers-2.7.0/bin/millennium":     "#!/bin/sh\n",
		"millenium-helpers-2.7.0/scripts/common.sh":  "# lib\n",
	}
	for name, body := range files {
		hdr := &tar.Header{Name: name, Mode: 0o644, Size: int64(len(body))}
		if err := tw.WriteHeader(hdr); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(body)); err != nil {
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

	extractDir := filepath.Join(dir, "out")
	if err := os.MkdirAll(extractDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := extractHelpersArchive(archivePath, extractDir); err != nil {
		t.Fatal(err)
	}
	root, err := findExtractedSourceRoot(extractDir)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(root) != "millenium-helpers-2.7.0" {
		t.Fatalf("root=%s", root)
	}
	if _, err := os.Stat(filepath.Join(root, "VERSION")); err != nil {
		t.Fatal(err)
	}
}

func TestExtractTarGzRejectsSlip(t *testing.T) {
	dir := t.TempDir()
	archivePath := filepath.Join(dir, "bad.tar.gz")
	f, err := os.Create(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	hdr := &tar.Header{Name: "../evil", Mode: 0o644, Size: 1}
	if err := tw.WriteHeader(hdr); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write([]byte("x")); err != nil {
		t.Fatal(err)
	}
	_ = tw.Close()
	_ = gz.Close()
	_ = f.Close()

	if err := extractHelpersArchive(archivePath, filepath.Join(dir, "out")); err == nil {
		t.Fatal("expected slip rejection")
	}
}
