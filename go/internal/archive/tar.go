package archive

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// SafeExtractTarGz extracts a .tar.gz into destDir, rejecting Zip Slip members.
func SafeExtractTarGz(archivePath, destDir string) error {
	if archivePath == "" || destDir == "" {
		return fmt.Errorf("Error: SafeExtractTarGz requires archive path and destination directory.")
	}
	if _, err := os.Stat(archivePath); err != nil {
		return fmt.Errorf("Error: Tar archive not found: %s", archivePath)
	}
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return err
	}
	destAbs, err := filepath.Abs(destDir)
	if err != nil {
		return err
	}
	if r, e := filepath.EvalSymlinks(destAbs); e == nil {
		destAbs = r
	}

	f, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("not a gzip archive: %w", err)
	}
	defer func() { _ = gz.Close() }()

	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		target, err := SafeJoinDest(destAbs, hdr.Name)
		if err != nil {
			return err
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, hdr.FileInfo().Mode())
			if err != nil {
				return err
			}
			if _, err := io.Copy(out, tr); err != nil {
				_ = out.Close()
				return err
			}
			if err := out.Close(); err != nil {
				return err
			}
		case tar.TypeSymlink, tar.TypeLink, tar.TypeChar, tar.TypeBlock, tar.TypeFifo:
			return fmt.Errorf("refusing unsupported tar member type %q (%q)", hdr.Typeflag, hdr.Name)
		default:
			// Skip uncommon types (e.g. extended headers) rather than writing unsafely.
			continue
		}
	}
	return nil
}
