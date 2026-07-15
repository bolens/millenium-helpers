//go:build windows

package repair

import (
	"os"

	"github.com/bolens/millenium-helpers/internal/steam"
)

func chownTree(path string) error {
	_ = path
	return nil
}

func ensureSteamClosedForRepair(yes bool) (relaunch bool, err error) {
	if os.Getenv("MOCK_LIB_DIR") != "" {
		return false, nil
	}
	if !steam.IsSteamRunning() {
		return false, nil
	}
	if err := steam.ConfirmClose(yes); err != nil {
		return false, err
	}
	return true, nil
}

func relaunchSteamAfterRepair() {
	if os.Getenv("MOCK_LIB_DIR") != "" {
		return
	}
	steam.RelaunchBestEffort()
}
