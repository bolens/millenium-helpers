//go:build windows

package upgrade

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/bolens/millenium-helpers/internal/steam"
	"github.com/bolens/millenium-helpers/internal/theme"
)

func rollbackPlatform(backupName string, o Options) error {
	steamDir := theme.FindSteamDir()
	if steamDir == "" {
		return fmt.Errorf("Error: Steam directory not found.")
	}
	bakRoot := EffectiveBackupDir()
	targetBackup := filepath.Join(bakRoot, backupName)
	if st, err := os.Stat(targetBackup); err != nil || !st.IsDir() {
		return fmt.Errorf("Error: Backup '%s' not found.", backupName)
	}

	steamRunning := steam.IsSteamRunning()
	if steamRunning {
		if err := steam.ConfirmClose(o.Yes); err != nil {
			return err
		}
	}

	millSrc, wsockSrc, err := resolveWindowsBackupContents(targetBackup)
	if err != nil {
		return err
	}
	millDest := filepath.Join(steamDir, "millennium")
	wsockDest := filepath.Join(steamDir, "wsock32.dll")

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
		steam.RelaunchBestEffort()
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
