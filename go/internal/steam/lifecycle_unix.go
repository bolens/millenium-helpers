//go:build unix

package steam

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// IsSteamRunning reports whether the Steam client process is present.
func IsSteamRunning() bool {
	if runtime.GOOS == "darwin" {
		return exec.Command("pgrep", "-ix", "Steam").Run() == nil
	}
	return exec.Command("pgrep", "-x", "steam").Run() == nil
}

// IsGameRunning detects an active Steam game (exit 75 path for scheduler).
func IsGameRunning() bool {
	if runtime.GOOS == "darwin" {
		out, err := exec.Command("ps", "-A", "-o", "command").CombinedOutput()
		if err != nil {
			return false
		}
		for _, line := range strings.Split(string(out), "\n") {
			if strings.Contains(line, "steamapps/common") && !strings.Contains(line, "grep") {
				return true
			}
		}
		return false
	}
	root := procRoot()
	entries, err := os.ReadDir(root)
	if err != nil {
		return false
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		pid := e.Name()
		if pid == "" || pid[0] < '0' || pid[0] > '9' {
			continue
		}
		comm, _ := os.ReadFile(filepath.Join(root, pid, "comm"))
		c := strings.TrimSpace(string(comm))
		if c == "steam" || c == "steamwebhelper" {
			continue
		}
		environ, err := os.ReadFile(filepath.Join(root, pid, "environ"))
		if err != nil {
			continue
		}
		for _, kv := range bytes.Split(environ, []byte{0}) {
			if bytes.HasPrefix(kv, []byte("SteamAppId=")) {
				id := string(kv[len("SteamAppId="):])
				if id != "" && id != "0" {
					return true
				}
			}
		}
	}
	return false
}

func currentUsername() string {
	u, err := user.Current()
	if err != nil {
		return ""
	}
	return u.Username
}

func flatpakSteamRunning(username string) bool {
	if _, err := exec.LookPath("flatpak"); err != nil {
		return false
	}
	var cmd *exec.Cmd
	if effectiveUID() == 0 && username != "" && username != currentUsername() {
		cmd = exec.Command("runuser", "-l", username, "-c", "flatpak ps")
	} else {
		cmd = exec.Command("flatpak", "ps")
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(string(out), "com.valvesoftware.Steam")
}

// CaptureEnv writes relaunch.env for a later post-update relaunch.
func CaptureEnv(username, home string) error {
	state := RelaunchStateFile(username, home)
	if err := os.MkdirAll(filepath.Dir(state), 0o700); err != nil {
		return err
	}
	if effectiveUID() == 0 {
		chownUser(filepath.Dir(state), username)
	}
	if runtime.GOOS == "darwin" {
		if err := os.WriteFile(state, []byte("export WAS_MACOS='true'\n"), 0o600); err != nil {
			return err
		}
		if effectiveUID() == 0 {
			chownUser(state, username)
		}
		return nil
	}

	wasFlatpak := flatpakSteamRunning(username)
	env := map[string]string{}
	steamArgs := ""
	pid := firstSteamPID()
	if pid != "" {
		root := procRoot()
		raw, _ := os.ReadFile(filepath.Join(root, pid, "environ"))
		for _, kv := range bytes.Split(raw, []byte{0}) {
			if len(kv) == 0 {
				continue
			}
			parts := bytes.SplitN(kv, []byte{'='}, 2)
			if len(parts) != 2 {
				continue
			}
			key := string(parts[0])
			for _, want := range EnvKeys {
				if key == want {
					env[key] = string(parts[1])
				}
			}
		}
		cmdRaw, _ := os.ReadFile(filepath.Join(root, pid, "cmdline"))
		args := bytes.Split(cmdRaw, []byte{0})
		var quoted []string
		for i, a := range args {
			if i == 0 || len(a) == 0 {
				continue
			}
			quoted = append(quoted, shellQuote(string(a)))
		}
		steamArgs = strings.Join(quoted, " ")
		if steamArgs != "" {
			steamArgs += " "
		}
	}
	if err := writeRelaunchEnv(state, env, steamArgs, wasFlatpak); err != nil {
		return err
	}
	if effectiveUID() == 0 {
		chownUser(state, username)
	}
	return nil
}

func firstSteamPID() string {
	out, err := exec.Command("pgrep", "-x", "steam").CombinedOutput()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			return line
		}
	}
	return ""
}

// CloseGracefully asks Steam to shut down, then force-kills if needed.
func CloseGracefully(username, home string) error {
	if runtime.GOOS == "darwin" {
		if testSuite() {
			fmt.Println("[TEST] Bypassing macOS Steam quit to protect host")
			fmt.Println("Steam closed successfully.")
			return nil
		}
		if currentUsername() == username {
			_ = exec.Command("osascript", "-e", `quit app "Steam"`).Run()
		} else {
			_ = exec.Command("runuser", "-l", username, "-c", `osascript -e 'quit app "Steam"'`).Run()
		}
		waitSteamGone(30 * time.Second)
		if IsSteamRunning() {
			fmt.Fprintln(os.Stderr, "Steam did not close gracefully. Force killing...")
			_ = exec.Command("killall", "-9", "Steam").Run()
		}
		fmt.Println("Steam closed successfully.")
		return nil
	}

	wasFlatpak := flatpakSteamRunning(username)
	state := RelaunchStateFile(username, home)
	var shutdown string
	switch {
	case wasFlatpak:
		shutdown = "flatpak run com.valvesoftware.Steam -shutdown"
	case lookPath("steam"):
		shutdown = "steam -shutdown"
	default:
		local := filepath.Join(home, ".local", "bin", "steam")
		if st, err := os.Stat(local); err == nil && !st.IsDir() && st.Mode()&0o111 != 0 {
			shutdown = local + " -shutdown"
		}
	}
	if shutdown != "" {
		_ = runSteamCmd(username, shutdown, state)
	}
	waitSteamGone(30 * time.Second)
	if IsSteamRunning() {
		fmt.Fprintln(os.Stderr, "Steam did not close gracefully. Force killing...")
		_ = exec.Command("killall", "-9", "steam", "steamwebhelper").Run()
	}
	fmt.Println("Steam closed successfully.")
	return nil
}

func waitSteamGone(d time.Duration) {
	deadline := time.Now().Add(d)
	for IsSteamRunning() && time.Now().Before(deadline) {
		time.Sleep(time.Second)
	}
}

func lookPath(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func runSteamCmd(username, cmd, stateFile string) error {
	envPrefix := ""
	if stateFile != "" {
		if st, err := os.Stat(stateFile); err == nil && st.Mode().IsRegular() {
			vals, err := ParseRelaunchEnv(stateFile)
			if err == nil {
				var parts []string
				for _, k := range EnvKeys {
					if v := vals[k]; v != "" {
						parts = append(parts, fmt.Sprintf("%s=%s", k, shellQuote(v)))
					}
				}
				if len(parts) > 0 {
					envPrefix = "env " + strings.Join(parts, " ") + " "
				}
			}
		}
	}
	full := envPrefix + cmd
	if testSuite() {
		if mock := os.Getenv("MOCK_BIN"); mock != "" {
			if _, err := os.Stat(filepath.Join(mock, "runuser")); err == nil {
				return exec.Command("runuser", username, "-c", full).Run()
			}
		}
		fmt.Printf("[TEST] Bypassing command execution to protect host: %s\n", full)
		return nil
	}
	if effectiveUID() == 0 {
		return exec.Command("runuser", username, "-c", full).Run()
	}
	return exec.Command("sh", "-c", full).Run()
}

// RelaunchFromState starts Steam using relaunch.env and deletes the file.
func RelaunchFromState(username, home string) (attempted bool, err error) {
	state := RelaunchStateFile(username, home)
	if !IsSafeRelaunchStateFile(username, state) {
		return false, nil
	}
	vals, err := ParseRelaunchEnv(state)
	if err != nil {
		return false, err
	}
	argDisplay := vals["STEAM_ARGS"]
	if argDisplay == "" {
		argDisplay = "none"
	}
	wasFlatpak := vals["WAS_FLATPAK"] == "true"
	fmt.Printf("Relaunching Steam client with arguments: %s (Flatpak: %v)...\n", argDisplay, wasFlatpak)
	_ = os.Remove(state)

	if testSuite() {
		fmt.Println("[TEST] Bypassing real Steam relaunch in test suite.")
		return true, nil
	}

	if runtime.GOOS == "darwin" {
		if currentUsername() == username {
			_ = exec.Command("open", "-a", "Steam").Start()
		} else {
			_ = exec.Command("runuser", "-l", username, "-c", "open -a Steam >/dev/null 2>&1 &").Start()
		}
		return true, nil
	}

	steamArgs := vals["STEAM_ARGS"]
	var cmd string
	switch {
	case wasFlatpak:
		cmd = "flatpak run com.valvesoftware.Steam " + steamArgs + " >/dev/null 2>&1 &"
	case lookPath("steam"):
		cmd = "steam " + steamArgs + " >/dev/null 2>&1 &"
	default:
		local := filepath.Join(home, ".local", "bin", "steam")
		if st, err := os.Stat(local); err == nil && !st.IsDir() {
			cmd = local + " " + steamArgs + " >/dev/null 2>&1 &"
		}
	}
	if cmd == "" {
		return true, nil
	}
	return true, runSteamCmd(username, cmd, "")
}
