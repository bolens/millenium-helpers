package install

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	defer func() { _ = out.Close() }()
	if _, err := io.Copy(out, in); err != nil {
		return err
	}
	return out.Chmod(mode)
}

func copyTreeFiles(srcDir, dstDir string, pattern string) error {
	matches, err := filepath.Glob(filepath.Join(srcDir, pattern))
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dstDir, 0o755); err != nil {
		return err
	}
	for _, src := range matches {
		st, err := os.Stat(src)
		if err != nil || st.IsDir() {
			continue
		}
		dst := filepath.Join(dstDir, filepath.Base(src))
		if err := copyFile(src, dst, 0o644); err != nil {
			return err
		}
	}
	return nil
}

func ensureDir(path string, dryRun bool, plan *[]string) error {
	*plan = append(*plan, "mkdir "+path)
	if dryRun {
		return nil
	}
	return os.MkdirAll(path, 0o755)
}

func planCopy(src, dst string, mode os.FileMode, dryRun bool, plan *[]string) error {
	*plan = append(*plan, fmt.Sprintf("install %s → %s", src, dst))
	if dryRun {
		return nil
	}
	return copyFile(src, dst, mode)
}

func planRemove(path string, dryRun bool, plan *[]string) error {
	*plan = append(*plan, "remove "+path)
	if dryRun {
		return nil
	}
	return os.RemoveAll(path)
}
