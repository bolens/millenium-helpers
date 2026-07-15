package schedule

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"

	"github.com/bolens/millenium-helpers/internal/steam"
)

const exitGameRunning = 75

// Test seam: override diag verification (defaults to exec millennium diag).
var verifyDiag = defaultVerifyDiag

func requireSchedulerGate() bool {
	if os.Getenv("MILLENNIUM_SCHEDULER") == "1" {
		return true
	}
	fmt.Fprintln(os.Stderr, "Error: pre-update is only for the scheduler. Do not invoke it manually.")
	fmt.Fprintln(os.Stderr, "Enable or run updates via: millennium schedule enable | millennium upgrade")
	return false
}

func requireSchedulerGatePost() bool {
	if os.Getenv("MILLENNIUM_SCHEDULER") == "1" {
		return true
	}
	fmt.Fprintln(os.Stderr, "Error: post-update is only for the scheduler. Do not invoke it manually.")
	fmt.Fprintln(os.Stderr, "Enable or run updates via: millennium schedule enable | millennium upgrade")
	return false
}

func rotateLogs(stateDir string) {
	logFile := filepath.Join(stateDir, "updater.log")
	st, err := os.Stat(logFile)
	if err != nil || !st.Mode().IsRegular() {
		return
	}
	const maxSize = 5 * 1024 * 1024
	if st.Size() <= maxSize {
		return
	}
	_ = os.Rename(logFile+".2", logFile+".3")
	_ = os.Rename(logFile+".1", logFile+".2")
	_ = copyFile(logFile, logFile+".1")
	_ = os.WriteFile(logFile, []byte("Log file rotated (exceeded 5MB limit).\n"), 0o644)
}

func copyFile(src, dst string) error {
	b, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, b, 0o644)
}

func defaultVerifyDiag() error {
	// Prefer long-name twin, then dispatcher + diag subcommand.
	if path, err := exec.LookPath("millennium-diag"); err == nil {
		cmd := exec.Command(path)
		cmd.Stdout = nil
		cmd.Stderr = nil
		return cmd.Run()
	}
	path, err := exec.LookPath("millennium")
	if err != nil {
		path = ResolvePackagedHelper("millennium")
	}
	if path == "" {
		return fmt.Errorf("millennium diag not found on PATH")
	}
	cmd := exec.Command(path, "diag")
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}

// runPreUpdate implements schedule pre-update (Unix/macOS). Windows returns an error.
func runPreUpdate() int {
	if runtime.GOOS == "windows" {
		fmt.Fprintln(os.Stderr, "Error: pre-update is not used on Windows (Task Scheduler runs upgrade directly).")
		return 1
	}
	if !requireSchedulerGate() {
		return 1
	}
	tu, err := ResolveTargetUser()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	rotateLogs(hookStateDir(tu))
	fmt.Println("Initiating pre-update checks...")
	if steam.IsGameRunning() {
		fmt.Println("A game is currently running under Steam. Aborting update run.")
		return exitGameRunning
	}
	if steam.IsSteamRunning() {
		fmt.Println("Steam is running. Closing Steam gracefully to perform upgrades...")
		if err := steam.CaptureEnv(tu.Name, tu.Home); err != nil {
			fmt.Fprintf(os.Stderr, "Error: capture Steam env: %v\n", err)
			return 1
		}
		if err := steam.CloseGracefully(tu.Name, tu.Home); err != nil {
			fmt.Fprintf(os.Stderr, "Error: close Steam: %v\n", err)
			return 1
		}
		fmt.Println("Steam closed successfully.")
	} else {
		fmt.Println("Steam is not running. No close required.")
	}
	return 0
}

// runPostUpdate implements schedule post-update (Unix/macOS).
func runPostUpdate() int {
	if runtime.GOOS == "windows" {
		fmt.Fprintln(os.Stderr, "Error: post-update is not used on Windows (Task Scheduler runs upgrade directly).")
		return 1
	}
	if !requireSchedulerGatePost() {
		return 1
	}
	fmt.Println("Initiating post-update checks and verification...")
	tu, err := ResolveTargetUser()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	stateFile := steam.RelaunchStateFile(tu.Name, tu.Home)
	if err := verifyDiag(); err != nil {
		fmt.Fprintln(os.Stderr, "Error: Millennium update failed verification checks. Relaunch cancelled.")
		_ = os.Remove(stateFile)
		return 1
	}
	fmt.Println("Diagnostics verification passed successfully.")
	attempted, err := steam.RelaunchFromState(tu.Name, tu.Home)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: relaunch Steam: %v\n", err)
		return 1
	}
	if !attempted {
		fmt.Println("No saved relaunch state found. Steam will not be restarted.")
	}
	return 0
}

// hookStateDir honors XDG_STATE_HOME for the current user (Bash rotate_logs parity).
func hookStateDir(tu TargetUser) string {
	if d := os.Getenv("MILLENNIUM_STATE_DIR"); d != "" {
		return d
	}
	if cur, err := user.Current(); err == nil && cur.Username == tu.Name {
		if xdg := os.Getenv("XDG_STATE_HOME"); xdg != "" {
			return filepath.Join(xdg, "millennium-helpers")
		}
	}
	return StateDirForUser(tu)
}
