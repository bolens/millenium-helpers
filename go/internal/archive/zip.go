// Package archive provides zip-slip–safe archive extraction.
package archive

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// SafeExtractZip extracts zipPath into destDir, rejecting zip-slip members.
func SafeExtractZip(zipPath, destDir string) error {
	if zipPath == "" || destDir == "" {
		return fmt.Errorf("Error: SafeExtractZip requires zip path and destination directory.")
	}
	if _, err := os.Stat(zipPath); err != nil {
		return fmt.Errorf("Error: Zip archive not found: %s", zipPath)
	}
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return err
	}
	destReal, err := filepath.Abs(destDir)
	if err != nil {
		return err
	}
	if r, e := filepath.EvalSymlinks(destReal); e == nil {
		destReal = r
	}

	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return fmt.Errorf("Error: Invalid zip archive: %w", err)
	}
	defer func() { _ = r.Close() }()

	for _, f := range r.File {
		if err := extractZipFile(f, destReal); err != nil {
			return err
		}
	}
	return nil
}

func extractZipFile(f *zip.File, destReal string) error {
	// Validate at the sink so CodeQL can see the Zip Slip guard.
	target, err := SafeJoinDest(destReal, f.Name)
	if err != nil {
		return fmt.Errorf("Error: Refusing zip member with unsafe path: %q", f.Name)
	}
	if f.FileInfo().IsDir() {
		return os.MkdirAll(target, 0o755)
	}
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer func() { _ = rc.Close() }()
	out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, f.Mode())
	if err != nil {
		return err
	}
	defer func() { _ = out.Close() }()
	_, err = io.Copy(out, rc)
	return err
}
