//go:build unix

package diag

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/bolens/millenium-helpers/internal/theme"
)

func doctorCloseSteam(yes bool) (relaunch bool, err error) {
	if isGameRunningUnix() {
		return false, fmt.Errorf("Error: A Steam game is currently running. Doctor repairs cannot proceed while a game is active.\nClose the running game, then re-run. Use --yes to skip the Steam close prompt.")
	}
	fmt.Println("Steam is currently running and must be closed to apply repairs to hooks/binaries.")
	if !yes {
		return false, fmt.Errorf("Error: Close Steam, or re-run with --yes / -y to stop Steam and continue.")
	}
	_ = exec.Command("pkill", "-x", "steam").Run()
	return true, nil
}

func doctorRelaunchSteam() {
	steam := theme.FindSteamDir()
	if steam == "" {
		return
	}
	for _, name := range []string{"steam", "steam.sh"} {
		p := filepath.Join(steam, name)
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			_ = exec.Command(p).Start()
			return
		}
	}
	_ = exec.Command("steam").Start()
}

func isGameRunningUnix() bool {
	// Best-effort: any process under steamapps besides steam* helpers.
	out, err := exec.Command("bash", "-c", `
pgrep -a steam >/dev/null || exit 1
ps -eo args= | grep -E '[Ss]teamapps' | grep -viE 'steamwebhelper|steamservice|steam\.exe|steam$' | grep -q . && exit 0
exit 1
`).CombinedOutput()
	_ = out
	return err == nil
}
