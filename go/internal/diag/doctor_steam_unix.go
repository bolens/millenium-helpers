//go:build unix

package diag

import (
	"fmt"

	"github.com/bolens/millenium-helpers/internal/steam"
)

func doctorCloseSteam(yes bool) (relaunch bool, err error) {
	if !steam.IsSteamRunning() {
		return false, nil
	}
	fmt.Println("Steam is currently running and must be closed to apply repairs to hooks/binaries.")
	if err := steam.ConfirmClose(yes); err != nil {
		return false, err
	}
	return true, nil
}

func doctorRelaunchSteam() {
	steam.RelaunchBestEffort()
}
