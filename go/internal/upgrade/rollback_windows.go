//go:build windows

package upgrade

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/bolens/millenium-helpers/internal/theme"
)

func rollbackPlatform(backupName string, o Options) error {
	steam := theme.FindSteamDir()
	if steam == "" {
		return fmt.Errorf("Error: Steam directory not found.")
	}
	bakRoot := EffectiveBackupDir()
	targetBackup := filepath.Join(bakRoot, backupName)
	if st, err := os.Stat(targetBackup); err != nil || !st.IsDir() {
		return fmt.Errorf("Error: Backup '%s' not found.", backupName)
	}

	if isWindowsGameRunning() {
		return fmt.Errorf("Error: A Steam game is currently running. Rollback aborted.\nClose the running game, then re-run. Use -Yes to skip the Steam close prompt.")
	}
	steamRunning := isWindowsSteamRunning()
	if steamRunning && !o.Yes {
		return fmt.Errorf("Error: Steam is running. Close Steam, or re-run with -Yes / --yes to stop Steam and continue.")
	}
	if steamRunning {
		_ = exec.Command("taskkill", "/F", "/IM", "steam.exe").Run()
	}

	millSrc, wsockSrc, err := resolveWindowsBackupContents(targetBackup)
	if err != nil {
		return err
	}
	millDest := filepath.Join(steam, "millennium")
	wsockDest := filepath.Join(steam, "wsock32.dll")

	if !o.Quiet {
		fmt.Printf("Rolling back Millennium installation to %s...\n", backupName)
	}
	_ = os.RemoveAll(millDest)
	_ = os.Remove(wsockDest)
	if err := copyDirTree(millSrc, millDest); err != nil {
		return fmt.Errorf("Error: Failed to restore millennium: %w", err)
	}
	if wsockSrc != "" {
		if err := copyFile(wsockSrc, wsockDest); err != nil {
			return fmt.Errorf("Error: Failed to restore wsock32.dll: %w", err)
		}
	}
	_ = os.RemoveAll(targetBackup)
	if !o.Quiet {
		fmt.Println("Rollback completed successfully.")
	}
	if steamRunning {
		steamExe := filepath.Join(steam, "steam.exe")
		_ = exec.Command(steamExe).Start()
		if !o.Quiet {
			fmt.Println("Steam relaunched.")
		}
	}
	return nil
}

// resolveWindowsBackupContents finds millennium tree + optional wsock32 in a backup dir.
// Supports PS layout (backup/millennium + backup/wsock32.dll) and flat Go layout
// (backup itself is the millennium tree).
func resolveWindowsBackupContents(bak string) (millSrc, wsockSrc string, err error) {
	nested := filepath.Join(bak, "millennium")
	if st, e := os.Stat(nested); e == nil && st.IsDir() {
		millSrc = nested
		w := filepath.Join(bak, "wsock32.dll")
		if _, e := os.Stat(w); e == nil {
			wsockSrc = w
		}
		return millSrc, wsockSrc, nil
	}
	if _, e := os.Stat(filepath.Join(bak, "version.txt")); e == nil {
		return bak, "", nil
	}
	return "", "", fmt.Errorf("Error: Backup '%s' does not contain a Millennium install.", filepath.Base(bak))
}

func isWindowsSteamRunning() bool {
	out, err := exec.Command("tasklist", "/FI", "IMAGENAME eq steam.exe").CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(out)), "steam.exe")
}

func isWindowsGameRunning() bool {
	// Heuristic used by Steam.ps1: steamwebhelper alone is client; games typically show as separate *.exe under Steam.
	// Port the PS Is-GameRunning check when available via PowerShell one-liner fallback.
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
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps)
	return cmd.Run() == nil
}
