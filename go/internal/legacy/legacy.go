package legacy

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// FeatureCommands are dispatcher feature names used for typo suggestions.
var FeatureCommands = []string{
	"diag", "doctor", "upgrade", "schedule", "theme", "repair", "purge", "mcp",
	"install", "uninstall",
}

// ScriptDir locates an install or checkout helpers directory for this OS.
// Preference order: MILLENNIUM_SCRIPTS_DIR, then peers of the running binary,
// then a walk from the working directory. Discovery keys on install layout
// (millennium.exe / VERSION markers), not feature script names.
func ScriptDir() string {
	if v := os.Getenv("MILLENNIUM_SCRIPTS_DIR"); v != "" {
		return v
	}
	exe, err := os.Executable()
	if err == nil {
		exe, _ = filepath.EvalSymlinks(exe)
		dir := filepath.Dir(exe)
		for _, candidate := range candidatesNear(dir) {
			if dirLooksLikeScripts(candidate) {
				return candidate
			}
		}
	}
	if wd, err := os.Getwd(); err == nil {
		for _, candidate := range []string{
			filepath.Join(wd, "scripts"),
			filepath.Join(wd, "scripts", "windows"),
			filepath.Join(wd, "..", "scripts"),
		} {
			if dirLooksLikeScripts(candidate) {
				return candidate
			}
		}
		dir := wd
		for i := 0; i < 6; i++ {
			unix := filepath.Join(dir, "scripts")
			win := filepath.Join(dir, "scripts", "windows")
			if runtime.GOOS == "windows" {
				if dirLooksLikeScripts(win) {
					return win
				}
			}
			if dirLooksLikeScripts(unix) {
				if runtime.GOOS == "windows" && dirLooksLikeScripts(win) {
					return win
				}
				if runtime.GOOS != "windows" {
					return unix
				}
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return ""
}

func candidatesNear(dir string) []string {
	out := []string{dir}
	if runtime.GOOS == "windows" {
		out = append(out,
			filepath.Join(dir, "scripts", "windows"),
			filepath.Join(dir, "..", "scripts", "windows"),
			filepath.Join(dir, "..", "..", "scripts", "windows"),
		)
	} else {
		out = append(out,
			filepath.Join(dir, "scripts"),
			filepath.Join(dir, "..", "scripts"),
			filepath.Join(dir, "..", "..", "scripts"),
			"/usr/lib/millennium-helpers",
		)
	}
	return out
}

func dirLooksLikeScripts(dir string) bool {
	if dir == "" {
		return false
	}
	if runtime.GOOS == "windows" {
		if _, err := os.Stat(filepath.Join(dir, "millennium.exe")); err == nil {
			return true
		}
		_, err := os.Stat(filepath.Join(dir, "windows", "millennium.exe"))
		return err == nil
	}
	// Installed lib dir (/usr/lib/millennium-helpers) or extract root.
	if _, err := os.Stat(filepath.Join(dir, "VERSION")); err == nil {
		return true
	}
	if _, err := os.Stat(filepath.Join(dir, "install.sh")); err == nil {
		return true
	}
	// Checkout: ScriptDir candidates are often …/scripts; markers live on parent.
	if filepath.Base(dir) == "scripts" {
		parent := filepath.Dir(dir)
		if _, err := os.Stat(filepath.Join(parent, "VERSION")); err == nil {
			return true
		}
		if _, err := os.Stat(filepath.Join(parent, "install.sh")); err == nil {
			return true
		}
	}
	return false
}

// KnownCommands returns dispatcher suggestion list including help.
func KnownCommands() []string {
	out := append([]string{}, FeatureCommands...)
	out = append(out, "help")
	return out
}

// IsFeature reports whether name is a feature command.
func IsFeature(name string) bool {
	name = strings.ToLower(name)
	for _, c := range FeatureCommands {
		if c == name {
			return true
		}
	}
	return false
}
