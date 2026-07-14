package legacy

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// FeatureCommands are dispatched to millennium-<name> legacy scripts.
var FeatureCommands = []string{
	"diag", "doctor", "upgrade", "schedule", "theme", "repair", "purge", "mcp",
}

// ScriptDir tries to locate the installed or checkout scripts directory for this OS.
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
		// Walk up looking for repo scripts/
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
		_, err := os.Stat(filepath.Join(dir, "millennium-diag.ps1"))
		return err == nil
	}
	// Unix entrypoints may be millenium-diag.sh in checkout or millennium-diag installed.
	for _, name := range []string{"millennium-diag.sh", "millennium-diag", "millennium-upgrade.sh"} {
		if _, err := os.Stat(filepath.Join(dir, name)); err == nil {
			return true
		}
	}
	return false
}

// ResolveCommand returns an *exec.Cmd that runs the legacy helper for shortName
// (diag, upgrade, …). doctor maps to millennium-diag with a leading "doctor" arg.
func ResolveCommand(shortName string, args []string) (*exec.Cmd, error) {
	if shortName == "doctor" {
		return ResolveCommand("diag", append([]string{"doctor"}, args...))
	}
	if shortName == "mcp" {
		return resolveMcp(args)
	}

	target := "millennium-" + shortName
	scriptDir := ScriptDir()

	if runtime.GOOS == "windows" {
		return resolveWindows(target, shortName, scriptDir, args)
	}
	return resolveUnix(target, shortName, scriptDir, args)
}

// resolveMcp finds PATH millennium-mcp or a checkout/install shim.
func resolveMcp(args []string) (*exec.Cmd, error) {
	if runtime.GOOS == "windows" {
		return resolveWindows("millennium-mcp", "mcp", ScriptDir(), args)
	}
	if path, err := exec.LookPath("millennium-mcp"); err == nil {
		return exec.Command(path, args...), nil
	}
	scriptDir := ScriptDir()
	candidates := []string{}
	if scriptDir != "" {
		candidates = append(candidates,
			filepath.Join(scriptDir, "millennium-mcp"),
			filepath.Join(scriptDir, "millennium-mcp.sh"),
		)
	}
	for _, p := range candidates {
		st, err := os.Stat(p)
		if err != nil || st.IsDir() {
			continue
		}
		return exec.Command(p, args...), nil
	}
	return nil, fmt.Errorf("Error: %q not found on PATH or in scripts dir", "millennium-mcp")
}

func resolveUnix(target, shortName, scriptDir string, args []string) (*exec.Cmd, error) {
	if path, err := exec.LookPath(target); err == nil {
		return exec.Command(path, args...), nil
	}
	if scriptDir != "" {
		for _, name := range []string{target, target + ".sh"} {
			p := filepath.Join(scriptDir, name)
			if st, err := os.Stat(p); err == nil && !st.IsDir() {
				cmd := exec.Command(p, args...)
				return cmd, nil
			}
		}
		// Checkout: scripts/millennium-diag.sh
		p := filepath.Join(scriptDir, "millennium-"+shortName+".sh")
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return exec.Command("bash", append([]string{p}, args...)...), nil
		}
	}
	return nil, fmt.Errorf("Error: %q not found on PATH or in scripts dir", target)
}

func resolveWindows(target, shortName, scriptDir string, args []string) (*exec.Cmd, error) {
	ps1 := target + ".ps1"
	var scriptPath string
	if scriptDir != "" {
		candidate := filepath.Join(scriptDir, ps1)
		if st, err := os.Stat(candidate); err == nil && !st.IsDir() {
			scriptPath = candidate
		}
		if scriptPath == "" {
			candidate = filepath.Join(scriptDir, "millennium-"+shortName+".ps1")
			if st, err := os.Stat(candidate); err == nil && !st.IsDir() {
				scriptPath = candidate
			}
		}
	}
	if scriptPath == "" {
		if path, err := exec.LookPath(ps1); err == nil {
			scriptPath = path
		}
	}
	if scriptPath == "" {
		return nil, fmt.Errorf("Error: %q not found", ps1)
	}
	shell := "pwsh"
	if _, err := exec.LookPath(shell); err != nil {
		shell = "powershell"
	}
	psArgs := []string{"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath}
	psArgs = append(psArgs, args...)
	return exec.Command(shell, psArgs...), nil
}

// RunLegacy executes the legacy helper and returns its exit code.
// Sets MILLENNIUM_LEGACY=1 so thin-wrapped long-name entrypoints keep their
// shell/PS install bodies instead of re-entering the Go dispatcher.
func RunLegacy(shortName string, args []string) int {
	cmd, err := ResolveCommand(shortName, args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "MILLENNIUM_LEGACY=1")
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode()
		}
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}

// KnownCommands returns dispatcher suggestion list including help.
func KnownCommands() []string {
	out := append([]string{}, FeatureCommands...)
	out = append(out, "help")
	return out
}

// IsFeature reports whether name is a legacy-delegated feature command.
func IsFeature(name string) bool {
	name = strings.ToLower(name)
	for _, c := range FeatureCommands {
		if c == name {
			return true
		}
	}
	return false
}
