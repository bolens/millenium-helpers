package version

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Version is set via -ldflags "-X github.com/bolens/millenium-helpers/internal/version.Version=..."
var Version = ""

// Resolve returns the helpers package version string.
func Resolve() string {
	if strings.TrimSpace(Version) != "" {
		return strings.TrimSpace(Version)
	}
	if v := readVERSIONNear(os.Args[0]); v != "" {
		return v
	}
	if wd, err := os.Getwd(); err == nil {
		if v := findVERSIONUp(wd); v != "" {
			return v
		}
	}
	return "dev"
}

// Print writes "name version X" matching shell helper style.
func Print(name string) {
	fmt.Printf("%s version %s\n", name, Resolve())
}

func readVERSIONNear(exe string) string {
	exe, err := filepath.Abs(exe)
	if err != nil {
		return ""
	}
	dir := filepath.Dir(exe)
	for _, candidate := range []string{
		filepath.Join(dir, "VERSION"),
		filepath.Join(dir, "..", "VERSION"),
		filepath.Join(dir, "..", "..", "VERSION"),
	} {
		if v := readFileTrim(candidate); v != "" {
			return v
		}
	}
	return ""
}

func findVERSIONUp(start string) string {
	dir := start
	for i := 0; i < 8; i++ {
		if v := readFileTrim(filepath.Join(dir, "VERSION")); v != "" {
			return v
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return ""
}

func readFileTrim(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}
