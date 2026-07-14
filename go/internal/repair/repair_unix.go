//go:build unix

package repair

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strconv"

	"github.com/bolens/millenium-helpers/internal/steam"
)

func chownTree(path string) error {
	uid, gid := repairOwnerIDs()
	return filepath.Walk(path, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		return os.Chown(p, uid, gid)
	})
}

func repairOwnerIDs() (uid, gid int) {
	uid = os.Getuid()
	gid = os.Getgid()
	if os.Geteuid() != 0 {
		return uid, gid
	}
	sudoUser := os.Getenv("SUDO_USER")
	if sudoUser == "" {
		return uid, gid
	}
	u, err := user.Lookup(sudoUser)
	if err != nil {
		return uid, gid
	}
	id, err1 := strconv.Atoi(u.Uid)
	gd, err2 := strconv.Atoi(u.Gid)
	if err1 != nil || err2 != nil {
		return uid, gid
	}
	return id, gd
}

func ensureSteamClosedForRepair(yes bool) (relaunch bool, err error) {
	// Offline / CI seam: do not touch a host Steam client under MOCK_LIB_DIR.
	if os.Getenv("MOCK_LIB_DIR") != "" {
		return false, nil
	}
	if steam.IsGameRunning() {
		return false, fmt.Errorf("Error: A Steam game is currently running. Repair aborted.\nClose the running game, then re-run.")
	}
	if !steam.IsSteamRunning() {
		return false, nil
	}
	username, home := repairSteamUserHome()
	if err := steam.CaptureEnv(username, home); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not capture Steam environment: %v\n", err)
	}
	if !yes {
		return false, fmt.Errorf("Error: Steam is running. Close Steam, or re-run with --yes (-y) to stop Steam and continue.")
	}
	if err := steam.CloseGracefully(username, home); err != nil {
		return false, err
	}
	return true, nil
}

func relaunchSteamAfterRepair() {
	if os.Getenv("MOCK_LIB_DIR") != "" {
		return
	}
	username, home := repairSteamUserHome()
	_, _ = steam.RelaunchFromState(username, home)
}

func repairSteamUserHome() (username, home string) {
	home, _ = os.UserHomeDir()
	username = os.Getenv("SUDO_USER")
	if username == "" {
		username = os.Getenv("USER")
	}
	if username == "" {
		if u, err := user.Current(); err == nil {
			username = u.Username
		}
	}
	if os.Geteuid() == 0 && os.Getenv("SUDO_USER") != "" {
		if u, err := user.Lookup(os.Getenv("SUDO_USER")); err == nil && u.HomeDir != "" {
			home = u.HomeDir
		}
	}
	return username, home
}
