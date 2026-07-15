// Package steam provides Steam client helpers for scheduler hooks and repairs.
package steam

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
)

// EnvKeys captured from a running Steam process for relaunch.
var EnvKeys = []string{
	"DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS",
	"WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP",
}

// TargetUser resolves SUDO_USER when elevated, else the current account.
func TargetUser() (name, home string, err error) {
	sudo := os.Getenv("SUDO_USER")
	if sudo != "" && effectiveUID() == 0 {
		u, err := user.Lookup(sudo)
		if err != nil {
			return "", "", fmt.Errorf("cannot resolve SUDO_USER %q: %w", sudo, err)
		}
		return u.Username, u.HomeDir, nil
	}
	u, err := user.Current()
	if err != nil {
		return "", "", err
	}
	return u.Username, u.HomeDir, nil
}

// RelaunchStateFile returns ~/.local/state/millennium-helpers/relaunch.env for the user.
func RelaunchStateFile(username, home string) string {
	cur, _ := user.Current()
	if cur != nil && cur.Username == username {
		if xdg := os.Getenv("XDG_STATE_HOME"); xdg != "" {
			return filepath.Join(xdg, "millennium-helpers", "relaunch.env")
		}
		if d := os.Getenv("MILLENNIUM_STATE_DIR"); d != "" {
			return filepath.Join(d, "relaunch.env")
		}
	}
	if d := os.Getenv("MILLENNIUM_STATE_DIR"); d != "" && (cur == nil || cur.Username == username) {
		return filepath.Join(d, "relaunch.env")
	}
	return filepath.Join(home, ".local", "state", "millennium-helpers", "relaunch.env")
}

// IsSafeRelaunchStateFile rejects symlinks and foreign-owned files.
func IsSafeRelaunchStateFile(username, path string) bool {
	if path == "" {
		return false
	}
	st, err := os.Lstat(path)
	if err != nil || st.Mode()&os.ModeSymlink != 0 || !st.Mode().IsRegular() {
		return false
	}
	owner, err := fileOwner(path)
	if err != nil || owner == "" {
		return true
	}
	return owner == username || owner == "root"
}

// ParseRelaunchEnv reads bash export lines from relaunch.env.
func ParseRelaunchEnv(path string) (map[string]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	out := make(map[string]string)
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")
		eq := strings.IndexByte(line, '=')
		if eq <= 0 {
			continue
		}
		key := line[:eq]
		val := unquoteShell(line[eq+1:])
		out[key] = val
	}
	return out, nil
}

func unquoteShell(s string) string {
	s = strings.TrimSpace(s)
	if len(s) >= 2 {
		if (s[0] == '\'' && s[len(s)-1] == '\'') || (s[0] == '"' && s[len(s)-1] == '"') {
			inner := s[1 : len(s)-1]
			if s[0] == '"' {
				inner = strings.ReplaceAll(inner, `\"`, `"`)
				inner = strings.ReplaceAll(inner, `\\`, `\`)
			}
			return inner
		}
	}
	return s
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func writeRelaunchEnv(path string, env map[string]string, steamArgs string, wasFlatpak bool) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "relaunch.env.*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	_ = tmp.Chmod(0o600)
	var b strings.Builder
	for _, k := range EnvKeys {
		if v, ok := env[k]; ok && v != "" {
			fmt.Fprintf(&b, "export %s=%s\n", k, shellQuote(v))
		}
	}
	fmt.Fprintf(&b, "export STEAM_ARGS=%s\n", shellQuote(steamArgs))
	fmt.Fprintf(&b, "export WAS_FLATPAK='%v'\n", wasFlatpak)
	if runtime.GOOS == "darwin" {
		fmt.Fprintf(&b, "export WAS_MACOS='true'\n")
	}
	if _, err := tmp.WriteString(b.String()); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return err
	}
	return os.Rename(tmpPath, path)
}

func procRoot() string {
	if d := os.Getenv("MOCK_PROC"); d != "" {
		return d
	}
	return "/proc"
}

func testSuite() bool {
	return os.Getenv("TEST_SUITE_RUN") != ""
}
