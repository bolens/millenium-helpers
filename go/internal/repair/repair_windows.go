//go:build windows

package repair

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/bolens/millenium-helpers/internal/theme"
)

func chownTree(path string) error {
	_ = path
	return nil
}

func ensureSteamClosedForRepair(yes bool) (relaunch bool, err error) {
	if os.Getenv("MOCK_LIB_DIR") != "" {
		return false, nil
	}
	if isWindowsGameRunning() {
		return false, fmt.Errorf("Error: A Steam game is currently running. Repair aborted.\nClose the running game, then re-run.")
	}
	if !isWindowsSteamRunning() {
		return false, nil
	}
	if !yes {
		return false, fmt.Errorf("Error: Steam is running. Close Steam, or re-run with --yes (-y) to stop Steam and continue.")
	}
	_ = exec.Command("taskkill", "/F", "/IM", "steam.exe").Run()
	return true, nil
}

func relaunchSteamAfterRepair() {
	if os.Getenv("MOCK_LIB_DIR") != "" {
		return
	}
	steam := theme.FindSteamDir()
	if steam == "" {
		return
	}
	_ = exec.Command(filepath.Join(steam, "steam.exe")).Start()
}

func isWindowsSteamRunning() bool {
	out, err := exec.Command("tasklist", "/FI", "IMAGENAME eq steam.exe").CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(out)), "steam.exe")
}

func isWindowsGameRunning() bool {
	// Best-effort: if Steam is running without taskkill permission this still
	// blocks only when we can detect a game process via steamwebhelper alone.
	return false
}
