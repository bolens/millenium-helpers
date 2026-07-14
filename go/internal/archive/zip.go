// Package archive provides zip-slip–safe archive extraction.
package archive

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
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
	defer r.Close()

	for _, f := range r.File {
		if !zipMemberSafe(f.Name, destReal) {
			return fmt.Errorf("Error: Refusing zip member with unsafe path: %q", f.Name)
		}
	}
	for _, f := range r.File {
		if err := extractZipFile(f, destReal); err != nil {
			return err
		}
	}
	return nil
}

func zipMemberSafe(member, destReal string) bool {
	name := strings.ReplaceAll(member, "\\", "/")
	name = strings.TrimSuffix(name, "/")
	if name == "" {
		return true
	}
	if strings.HasPrefix(name, "/") || (len(name) >= 2 && name[1] == ':') {
		return false
	}
	parts := strings.Split(name, "/")
	for _, p := range parts {
		if p == ".." {
			return false
		}
	}
	target := filepath.Join(append([]string{destReal}, parts...)...)
	target = filepath.Clean(target)
	sep := string(os.PathSeparator)
	return target == destReal || strings.HasPrefix(target, destReal+sep)
}

func extractZipFile(f *zip.File, destReal string) error {
	name := strings.ReplaceAll(f.Name, "\\", "/")
	parts := strings.Split(strings.TrimSuffix(name, "/"), "/")
	target := filepath.Join(append([]string{destReal}, parts...)...)
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
	defer rc.Close()
	out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, f.Mode())
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, rc)
	return err
}
