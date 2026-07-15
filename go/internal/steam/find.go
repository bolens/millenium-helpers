package steam

import (
	"os"
	"path/filepath"
	"runtime"
)

// FindDir returns the first existing Steam install root, or "".
func FindDir() string {
	for _, c := range dirCandidates() {
		if c == "" {
			continue
		}
		if st, err := os.Stat(c); err == nil && st.IsDir() {
			return c
		}
	}
	return ""
}

// DirCandidates returns likely Steam roots (may not exist).
func DirCandidates() []string {
	return dirCandidates()
}

func dirCandidatesUnix() []string {
	home, _ := os.UserHomeDir()
	return []string{
		filepath.Join(home, ".local/share/Steam"),
		filepath.Join(home, ".steam/steam"),
		filepath.Join(home, ".steam/root"),
		filepath.Join(home, ".var/app/com.valvesoftware.Steam/.local/share/Steam"),
		filepath.Join(home, "Library/Application Support/Steam"),
		os.Getenv("STEAM"),
	}
}

func dirCandidatesCommon() []string {
	var out []string
	for _, env := range []string{"STEAM", "STEAM_PATH"} {
		if v := os.Getenv(env); v != "" {
			out = append(out, v)
		}
	}
	if runtime.GOOS != "windows" {
		return append(out, dirCandidatesUnix()...)
	}
	return out
}
