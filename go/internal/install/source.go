package install

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

// FindSourceRoot walks from start (or cwd) looking for a helpers checkout/extract root
// (VERSION + go/cmd/millennium or bin/millennium).
func FindSourceRoot(explicit string) (string, error) {
	if explicit != "" {
		if looksLikeSourceRoot(explicit) {
			return filepath.Clean(explicit), nil
		}
		return "", fmt.Errorf("source root %q does not look like a helpers tree", explicit)
	}
	if v := os.Getenv("MILLENNIUM_SOURCE_ROOT"); v != "" {
		if looksLikeSourceRoot(v) {
			return filepath.Clean(v), nil
		}
	}
	wd, err := os.Getwd()
	if err != nil {
		wd = "."
	}
	dir := wd
	for i := 0; i < 8; i++ {
		if looksLikeSourceRoot(dir) {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	// Near the running executable (installed / release layout).
	if exe, err := os.Executable(); err == nil {
		exe, _ = filepath.EvalSymlinks(exe)
		dir := filepath.Dir(exe)
		for _, c := range []string{
			dir,
			filepath.Join(dir, ".."),
			filepath.Join(dir, "..", ".."),
		} {
			if looksLikeSourceRoot(c) {
				return filepath.Clean(c), nil
			}
		}
	}
	return "", fmt.Errorf("could not find helpers source root (set --source-root or MILLENNIUM_SOURCE_ROOT)")
}

func looksLikeSourceRoot(dir string) bool {
	if dir == "" {
		return false
	}
	if _, err := os.Stat(filepath.Join(dir, "VERSION")); err != nil {
		return false
	}
	if _, err := os.Stat(filepath.Join(dir, "go", "cmd", "millennium")); err == nil {
		return true
	}
	bin := "millennium"
	if runtime.GOOS == "windows" {
		bin = "millennium.exe"
	}
	if _, err := os.Stat(filepath.Join(dir, "bin", bin)); err == nil {
		return true
	}
	if runtime.GOOS == "windows" {
		if _, err := os.Stat(filepath.Join(dir, "scripts", "windows", "millennium.exe")); err == nil {
			return true
		}
	}
	return false
}

// ResolveDispatcherBinary finds the millennium binary to install.
func ResolveDispatcherBinary(sourceRoot, explicit string) (string, error) {
	if explicit != "" {
		if st, err := os.Stat(explicit); err == nil && !st.IsDir() {
			return explicit, nil
		}
		return "", fmt.Errorf("dispatcher binary not found: %s", explicit)
	}
	bin := "millennium"
	if runtime.GOOS == "windows" {
		bin = "millennium.exe"
	}
	candidates := []string{
		filepath.Join(sourceRoot, "bin", bin),
	}
	if runtime.GOOS == "windows" {
		candidates = append(candidates, filepath.Join(sourceRoot, "scripts", "windows", bin))
	}
	if exe, err := os.Executable(); err == nil {
		candidates = append([]string{exe}, candidates...)
	}
	for _, c := range candidates {
		if st, err := os.Stat(c); err == nil && !st.IsDir() {
			return c, nil
		}
	}
	return "", fmt.Errorf("Go dispatcher %s not found under %s (run make build)", bin, sourceRoot)
}
