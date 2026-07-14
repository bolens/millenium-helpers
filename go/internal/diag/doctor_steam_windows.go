//go:build windows

package diag

import (
	"fmt"
	"os/exec"
	"path/filepath"

	"github.com/bolens/millenium-helpers/internal/theme"
)

func doctorCloseSteam(yes bool) (relaunch bool, err error) {
	if isGameRunningWindows() {
		return false, fmt.Errorf("Error: A Steam game is currently running. Doctor repairs cannot proceed.\nClose the running game, then re-run. Use -Yes to skip the Steam close prompt.")
	}
	fmt.Println("Steam is currently running and must be closed to apply binary repairs.")
	if !yes {
		return false, fmt.Errorf("Error: Close Steam, or re-run with -Yes / --yes to stop Steam and continue.")
	}
	_ = exec.Command("taskkill", "/F", "/IM", "steam.exe").Run()
	return true, nil
}

func doctorRelaunchSteam() {
	steam := theme.FindSteamDir()
	if steam == "" {
		return
	}
	_ = exec.Command(filepath.Join(steam, "steam.exe")).Start()
}

func isGameRunningWindows() bool {
	ps := `
$ErrorActionPreference='SilentlyContinue'
$steam = Get-Process steam -ErrorAction SilentlyContinue
if (-not $steam) { exit 1 }
$games = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -ne 'steam.exe' -and $_.Name -ne 'steamwebhelper.exe' -and $_.Name -ne 'steamservice.exe' -and
  $_.ExecutablePath -and $_.ExecutablePath -like '*steamapps*'
}
if ($games) { exit 0 } else { exit 1 }
`
	return exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps).Run() == nil
}
